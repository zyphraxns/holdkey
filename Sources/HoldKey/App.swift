import SwiftUI
import AppKit
import CoreGraphics
import ApplicationServices

@main
struct HoldKeyApp: App {
    init() {
        Log.write("app init")
        // 自检模式：不启动 UI，直接验证「发一次 keyDown → 等 N 秒 → 发 keyUp」这条主链路。
        // 用法：HoldKey --selftest [秒数]
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()
        }
        // --windump：等面板出现后，把 app 自己所有窗口的真实位置打到 stderr。
        // 外部用 CGWindowList 读到的坐标可能是「另一个 Space」的偏移值，
        // 只有进程内部拿到的 frame 才是可信的。
        if CommandLine.arguments.contains("--windump") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                for (i, w) in NSApp.windows.enumerated() {
                    let f = w.frame
                    FileHandle.standardError.write(
                        "WIN[\(i)] class=\(type(of: w)) frame=(\(Int(f.origin.x)),\(Int(f.origin.y)) \(Int(f.width))x\(Int(f.height))) visible=\(w.isVisible) level=\(w.level.rawValue) onScreen=\(w.isOnActiveSpace)\n"
                            .data(using: .utf8)!)
                }
                exit(0)
            }
        }
    }

    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var engine = HoldEngine()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(engine: engine)
        } label: {
            // 待命只显示键盘图标；运行时菜单栏直接显示「预设名 · Ns」。
            if engine.isRunning {
                Text("\(engine.activePresetName) · \(Int(engine.remaining.rounded()))s")
            } else {
                Image(systemName: "keyboard")
            }
        }
        .menuBarExtraStyle(.window)

        Window("设置", id: "settings") {
            SettingsView(engine: engine)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("didFinishLaunching ax=\(Permissions.isAccessibilityTrusted) postEvent=\(Permissions.canPostEvents)")

        // SIGKILL / 崩溃不可能被捕获，那种情况下键会一直是按住的状态。
        // 既然刚启动时我们一定没按任何键，就顺手把「上次遗留的按住状态」清掉
        // —— 这是唯一能给不可捕获地终止收尾的时机。
        clearStaleHeldKeys()
        // 启动时如果没有权限，主动弹一次系统授权（事后系统只会提示一次，之后要用户自己去勾）
        if !Permissions.allGood {
            Permissions.requestAccessibility()
        }
        // 不在 Dock 里显示，纯菜单栏
        NSApp.setActivationPolicy(.accessory)

        // 所有可能让键卡住的路径都补 keyUp
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            HeldKeys.shared.releaseAll()
        }
        nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            // 退到后台不一定该松键（切窗口时游戏本来就收不到），但保证状态一致
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            HeldKeys.shared.releaseAll()
        }
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in
            HeldKeys.shared.releaseAll()
        }
        ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { _ in
            HeldKeys.shared.releaseAll()
        }
        ws.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { _ in
            HeldKeys.shared.releaseAll()
        }

        // SIGINT / SIGTERM / SIGHUP 也要松键（命令行启动、kill 的情况）
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler {
                HeldKeys.shared.releaseAll()
                exit(0)
            }
            src.resume()
            SignalBox.keep.append(src)
        }
    }

    /// 启动时清理上次遗留的按住状态。
    /// 只清理我们自己的预设键，避免误动用户手上真正按着的键。
    private func clearStaleHeldKeys() {
        var cleared: [String] = []
        for key in HoldableKey.all {
            guard CGEventSource.keyState(.combinedSessionState, key: key.vk) else { continue }
            if let src = KeyPresser.makeSource() {
                KeyPresser.post(vk: key.vk, down: false, isRepeat: false, source: src)
                usleep(45_000)
                KeyPresser.post(vk: key.vk, down: false, isRepeat: false, source: src)
            }
            if CGEventSource.keyState(.combinedSessionState, key: key.vk) {
                cleared.append("\(key.label)(失败)")
            } else {
                cleared.append(key.label)
            }
        }
        if !cleared.isEmpty {
            Log.write("启动清理遗留按键: \(cleared.joined(separator: ", "))")
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        HeldKeys.shared.releaseAll()
        return .terminateNow
    }
}

enum SignalBox {
    nonisolated(unsafe) static var keep: [DispatchSourceSignal] = []
}


enum SelfTest {
    static func run() -> Never {
        let args = CommandLine.arguments
        var secs = 2.0
        if let i = args.firstIndex(of: "--selftest"), i + 1 < args.count, let v = Double(args[i + 1]) {
            secs = v
        }
        // --plain：只发一次 keyDown，不补发重复事件（对照组）
        let useAutorepeat = !args.contains("--plain")
        // 走 stderr 而不是 Log：被终端拉起来时进程继承了终端的沙箱，写不了 ~/Library/Logs，
        // 那种情况下日志会静默失败，排查问题时反而误导。stderr 永远看得见。
        let ax = Permissions.isAccessibilityTrusted
        let post = Permissions.canPostEvents
        warn("selftest: 权限 ax=\(ax) postEvent=\(post) allGood=\(Permissions.allGood)")
        if !Permissions.allGood {
            warn("selftest: 没有合成事件权限，按键会被系统丢掉（不是代码问题）")
        }
        warn("selftest: 按住 W \(secs) 秒 (autorepeat=\(useAutorepeat))")
        let sem = DispatchSemaphore(value: 0)
        Task {
            await KeyPresser.hold(vk: 0x0D, seconds: secs, useAutorepeat: useAutorepeat)
            sem.signal()
        }
        sem.wait()
        warn("selftest: 完成，未残留按键=\(HeldKeys.shared.count == 0)")
        exit(0)
    }

    private static func warn(_ s: String) {
        FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
    }
}