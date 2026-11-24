import Foundation
import SwiftUI
import CoreGraphics
import AppKit
import Carbon.HIToolbox

/// 可选的按键。只放游戏里真正常用的移动键，避免用户随手设成 Cmd 之类把系统搞乱。
struct HoldableKey: Identifiable, Hashable {
    let id: String
    let label: String
    let vk: CGKeyCode
    let symbol: String

    static let all: [HoldableKey] = [
        .init(id: "w",     label: "W",     vk: 0x0D, symbol: "arrow.up"),
        .init(id: "a",     label: "A",     vk: 0x00, symbol: "arrow.left"),
        .init(id: "s",     label: "S",     vk: 0x01, symbol: "arrow.down"),
        .init(id: "d",     label: "D",     vk: 0x02, symbol: "arrow.right"),
        .init(id: "space", label: "空格",  vk: 0x31, symbol: "space"),
        .init(id: "shift", label: "Shift", vk: 0x38, symbol: "shift"),
        .init(id: "ctrl",  label: "Ctrl",  vk: 0x3B, symbol: "control"),
        .init(id: "e",     label: "E",     vk: 0x0E, symbol: "e.circle"),
        .init(id: "f",     label: "F",     vk: 0x03, symbol: "f.circle"),
    ]

    static func byID(_ id: String) -> HoldableKey { all.first { $0.id == id } ?? all[0] }
}

@MainActor
final class HoldEngine: ObservableObject {
    // 用户设置（持久化）
    @AppStorage("hold.useAutorepeat") var useAutorepeat: Bool = true
    /// 四个固定预设槽。整段 JSON 存在 UserDefaults 里，避免四个槽各自拆字段、升级时错位。
    @AppStorage("hold.presets.v1") private var presetsJSON: String = ""
    /// 当前选中的预设槽（0–3）
    @AppStorage("hold.selectedPreset") var selectedPresetID: Int = 0 {
        didSet { objectWillChange.send() }
    }

    // 运行状态
    @Published private(set) var isRunning = false
    @Published private(set) var remaining: Double = 0
    @Published private(set) var lastMessage: String = ""
    /// 正在运行的预设名，供菜单栏显示；待命时清空。
    @Published private(set) var activePresetName: String = ""
    @Published private(set) var hotKeyAvailable: Bool = true
    /// 当前是否真的能把合成按键送进系统
    @Published private(set) var permissionsOK: Bool = Permissions.allGood
    /// 全局热键是否启用
    @Published var hotKeyEnabled: Bool = true {
        didSet { rebuildHotKeys() }
    }

    /// 从持久化数据解码出来的四个预设。设置页会通过 setPreset 修改它。
    private(set) var presets: [HoldPreset] = PresetDefaults.all
    private var hotKeys: [UInt32: GlobalHotKey] = [:]

    private var task: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var permTimer: Timer?
    private var focusObserver: NSObjectProtocol?
    private var keyWindowObserver: NSObjectProtocol?
    private var runID: UUID?
    private var targetPID: pid_t?
    /// 面板打开前谁在最前 —— 开火前要把它切回来，否则合成的按键会打进我们自己的面板
    private(set) var previousApp: NSRunningApplication?

    init() {
        loadPresets()
        rebuildHotKeys()
        startPermissionPolling()
        startTrackingFocus()
    }

    deinit {
        if let focusObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(focusObserver)
        }
        if let keyWindowObserver { NotificationCenter.default.removeObserver(keyWindowObserver) }
    }

    // MARK: - 焦点

    /// 记住「上一个前台应用」。
    ///
    /// 为什么非做不可：点菜单栏图标本身就会把 HoldKey 变成前台应用，
    /// 而 CGEvent 投递到 cghidEventTap 后是给「当前 key window」的 ——
    /// 也就是说，如果这时不切回去，W 会被打进我们自己的面板，游戏一动不动。
    private func startTrackingFocus() {
        // 先记一次「启动时谁在前台」。
        // 只在 didActivate 里记是不够的：如果 HoldKey 起来时目标程序早就在前台、
        // 之后用户没再切换过窗口，previousApp 会一直是 nil（实测就是 focus=nil）。
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }

        focusObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                let pid = app.processIdentifier
                if pid != ProcessInfo.processInfo.processIdentifier { self.previousApp = app }
                if let targetPID = self.targetPID, pid != targetPID {
                    self.stop(reason: "已切换应用，停止长按")
                }
            }
        }
        // 菜单栏面板可以获得键盘焦点，即使系统仍把游戏显示为前台应用。
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.targetPID != nil { self?.stop(reason: "HoldKey 面板获得焦点，停止长按") }
            }
        }
    }

    /// 让出 HoldKey 自己的键盘焦点，返回本次按键的目标进程。
    private func restoreFocus() -> pid_t? {
        // 判断依据不能只看 frontmostApplication。
        //
        // 踩过的坑（实测证据）：MenuBarExtra 的面板是 nonactivating panel，
        // 点开面板后 NSApp.isActive=true、keyWindow=MenuBarExtraWindow，
        // 但 NSWorkspace.frontmostApplication 仍是 Safari/游戏。
        // 于是旧代码的 `guard frontPid == selfPid` 直接 return false，什么都不做，
        // 合成的 W 全打进了面板的「按住 [ ] 秒」输入框（输入框变成 "1wwwwww..."）。
        //
        // 所以真正的判据是「键盘焦点还在不在我们身上」，keyWindow 才是那个信号。
        let selfPid = ProcessInfo.processInfo.processIdentifier
        let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ourWindowIsKey = NSApp.keyWindow != nil
        guard ourWindowIsKey || frontPid == selfPid else { return frontPid }

        // 只 resignKey，不要 NSApp.hide(nil)。
        // 理由：面板是 nonactivating panel，它只是「占着 key window」，app 并没有真的到前台；
        // hide 对 accessory app 会把状态栏图标一起藏掉，用户会以为程序挂了。
        // resignKey 之后面板仍然可见（倒计时照样能看），但按键不会再进输入框。
        if ourWindowIsKey {
            NSApp.keyWindow?.resignKey()
        }

        // 优先用「此刻真正的 frontmost」，而不是缓存的 previousApp。
        //
        // 为什么：previousApp 是启动/切窗时记下的，可能早就过期。
        // 实测到过一次 previousApp=Safari（几分钟前的前台），而当时真正的目标程序是别的，
        // 结果 activate() 把焦点还给了错误的 app，按键全丢（sink 收到 downs=0）。
        //
        // 能这么写的前提：面板是 nonactivating panel，它占住 key window 时
        // NSWorkspace.frontmostApplication 仍然是游戏本身（实测确认）。
        // 所以开火这一刻读到的 frontmost 就是正确答案。
        let live = NSWorkspace.shared.frontmostApplication
        if let target = live, target.processIdentifier != selfPid, !target.isTerminated {
            target.activate()
            return target.processIdentifier
        }

        // 退路：frontmost 就是我们自己（用户刚在面板里点过东西），才用缓存的记录。
        if let app = previousApp, !app.isTerminated, app.processIdentifier != selfPid {
            // macOS 14 起 ignoringOtherApps 已无作用，用不带 option 的 activate
            app.activate()
            return app.processIdentifier
        }
        // 注意：这里不要「兜底激活 frontmost」。
        // 试过一版是这么写的，结果热键路径上把焦点从 sink 抢给了 GFN
        // （测到的直接证据：按下热键后 sink 在 t=1.403 收到 KEY-WINDOW RESIGNED，app=NVIDIA GeForce NOW）。
        return nil
    }

    // MARK: - 权限自检

    /// 合成按键需要辅助功能权限。缺权限时 CGEvent 会静默失败，
    /// 所以这里的状态必须反映到界面上，不能只是内部判断。
    var hasPostEventAccess: Bool { Permissions.allGood }

    func refreshPermissions() {
        let ok = Permissions.allGood
        if ok != permissionsOK { permissionsOK = ok }
        if ok {
            // 刚拿到权限时，主动请求一次，让系统把它记住
            Permissions.requestPostEventAccess()
        } else {
            Permissions.requestAccessibility()
        }
        Log.write("refreshPermissions ok=\(ok)")
    }

    func openAccessibilitySettings() {
        Permissions.openAccessibilityPane()
    }

    /// 用户去系统设置里勾完权限、切回来时，界面应该自己变好。
    /// 不轮询的话，用户只会看到那个橙色横幅一直挂着，以为没生效。
    /// 注意：这里只读状态，绝不调用 request*，否则每个 2 秒就弹一次系统框。
    private func startPermissionPolling() {
        permTimer?.invalidate()
        permTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let ok = Permissions.allGood
                guard ok != self.permissionsOK else { return }
                self.permissionsOK = ok
                Log.write("permission changed -> \(ok)")
            }
        }
    }

    // MARK: - 热键

    private func loadPresets() {
        guard !presetsJSON.isEmpty,
              let data = presetsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([HoldPreset].self, from: data),
              decoded.count == PresetDefaults.all.count else {
            presets = PresetDefaults.all
            return
        }
        // 手工改过 UserDefaults / 旧版本数据可能带 Ctrl 或无修饰键，坚决不加载。
        let valid = decoded.enumerated().allSatisfy { i, preset in
            preset.id == i &&
            !preset.hotKey.containsControl &&
            preset.hotKey.modifiers & (UInt32(optionKey) | UInt32(cmdKey) | UInt32(shiftKey)) != 0 &&
            preset.seconds.isFinite && preset.seconds > 0
        }
        presets = valid ? decoded : PresetDefaults.all
    }

    private func savePresets() {
        guard let data = try? JSONEncoder().encode(presets),
              let s = String(data: data, encoding: .utf8) else { return }
        presetsJSON = s
    }

    /// 改某个预设的字段；UI 绑定都会走这里，保证内存与持久化同步。
    func updatePreset(id: Int, name: String? = nil, keyID: String? = nil,
                      seconds: Double? = nil, hotKey: HotKeyCombo? = nil) {
        guard let i = presets.firstIndex(where: { $0.id == id }) else { return }
        if let name { presets[i].name = name }
        if let keyID { presets[i].keyID = keyID }
        if let seconds { presets[i].seconds = seconds }
        if let hotKey { presets[i].hotKey = hotKey }
        savePresets()
        objectWillChange.send()
        rebuildHotKeys()
    }

    var selectedPreset: HoldPreset {
        presets.first { $0.id == selectedPresetID } ?? presets[0]
    }

    func selectPreset(id: Int) {
        guard presets.contains(where: { $0.id == id }) else { return }
        selectedPresetID = id
    }

    // MARK: - 热键

    private func rebuildHotKeys() {
        hotKeys.removeAll()   // 旧 GlobalHotKey deinit 会自动注销
        guard hotKeyEnabled else {
            hotKeyAvailable = false
            return
        }
        // 每个预设独立注册：⌥⌘H / ⌥⌘J / ⌥⌘K / ⌥⌘L
        for p in presets {
            let thisID = p.id
            let hk = GlobalHotKey(id: UInt32(thisID + 1),
                                  keyCode: p.hotKey.keyCode,
                                  modifiers: p.hotKey.modifiers) { [weak self] in
                Task { @MainActor in self?.hotKeyFired(presetID: thisID) }
            }
            if let hk { hotKeys[UInt32(thisID)] = hk }
        }
        hotKeyAvailable = hotKeys.count == presets.count
        Log.write("rebuildHotKeys enabled=\(hotKeyEnabled) registered=\(hotKeys.count)/\(presets.count)")
    }

    private func hotKeyFired(presetID: Int) {
        selectPreset(id: presetID)
        if isRunning { stop(reason: "手动停止") } else { fire(presetID: presetID) }
    }

    // MARK: - 触发 / 停止

    func toggle() {
        hotKeyFired(presetID: selectedPresetID)
    }

    func fire(presetID: Int? = nil) {
        guard !isRunning else { return }
        if let presetID { selectPreset(id: presetID) }
        let preset = selectedPreset

        // 硬闸门：没权限就不启动，否则用户只会看到「按了没反应」这种最难查的现象
        if !permissionsOK {
            permissionsOK = Permissions.allGood
            Permissions.requestPostEventAccess()
        }
        if !permissionsOK {
            lastMessage = "缺少辅助功能权限，按键发不出去"
            Log.write("fire blocked: no permission")
            return
        }

        var secs = preset.seconds
        if !secs.isFinite || secs <= 0 { secs = 30 }
        // 硬上限，防止手滑输入 999999 把键按死
        let cap: Double = 60 * 30
        secs = min(secs, cap)

        let key = HoldableKey.byID(preset.keyID)

        // 关键一步：先把焦点还给游戏，再开始发键。
        // 顺序不能反 —— 先发键再切窗口，开头那一小段会打进我们自己的面板。
        guard let target = restoreFocus() else {
            lastMessage = "找不到目标应用，长按未启动"
            return
        }
        let id = UUID()
        runID = id
        targetPID = target
        isRunning = true
        // 诊断用：把「我们自己此刻是否还占着键盘焦点」记下来。
        // 面板是 nonactivating panel，可能在我们不是前台应用的情况下自己成为 key window，
        // 这时合成的按键会打进面板的输入框而不是游戏 —— 光看 frontmostApplication 发现不了。
        let kw = NSApp.keyWindow
        Log.write("fire key=\(key.label) vk=\(key.vk) secs=\(secs) focus=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil") prev=\(previousApp?.localizedName ?? "nil") selfActive=\(NSApp.isActive) keyWindow=\(kw.map { String(describing: type(of: $0)) } ?? "nil")")
        remaining = secs
        activePresetName = preset.name
        lastMessage = "按住 \(preset.name) · \(key.label) \(fmt(secs))"

        let repeatEnabled = useAutorepeat
        task = Task { [weak self] in
            // 给面板让出键盘焦点留一点时间，取消时直接退出。
            do { try await Task.sleep(nanoseconds: 120_000_000) } catch { return }
            let completed = await KeyPresser.hold(vk: key.vk, seconds: secs, useAutorepeat: repeatEnabled) { [weak self] in
                guard self?.runID == id else { return false }
                return NSApp.keyWindow == nil && NSWorkspace.shared.frontmostApplication?.processIdentifier == target
            }
            guard let self, self.runID == id else { return }
            self.resetRun()
            self.lastMessage = completed ? "完成：按住 \(preset.name) · \(key.label) \(self.fmt(secs))" : "长按已中断"
        }
        startTicker(total: secs)
    }

    func stop(reason: String = "已停止") {
        guard isRunning else {
            // 即使没在跑，也扫一遍残留，保证幂等安全
            HeldKeys.shared.releaseAll()
            return
        }
        let released = cancelRun()
        lastMessage = released.isEmpty ? reason : "\(reason)（已补发 keyUp）"
    }

    /// 退出/休眠/锁屏等所有异常路径都走这里。
    func emergencyRelease(reason: String) {
        cancelRun()
        lastMessage = reason
    }

    @discardableResult
    private func cancelRun() -> [CGKeyCode] {
        task?.cancel()
        resetRun()
        return HeldKeys.shared.releaseAll()
    }

    private func resetRun() {
        runID = nil
        targetPID = nil
        task = nil
        ticker?.cancel()
        ticker = nil
        isRunning = false
        remaining = 0
        activePresetName = ""
    }

    private func startTicker(total: Double) {
        ticker?.cancel()
        let started = Date()
        ticker = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled { break }
                await MainActor.run {
                    guard self.isRunning else { return }
                    let used = Date().timeIntervalSince(started)
                    self.remaining = max(0, total - used)
                }
            }
        }
    }

    private func fmt(_ s: Double) -> String {
        s == s.rounded() ? "\(Int(s)) 秒" : String(format: "%.1f 秒", s)
    }
}
