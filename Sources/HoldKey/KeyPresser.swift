import Foundation
import CoreGraphics
import Darwin
import AppKit

/// 负责真正把按键事件投进系统。
/// 关键点全部来自实测/外部证据：
///  - 必须用 .hidSystemState 事件源，否则没有 HID 状态、timestamp 为 0，Wine/部分游戏会丢弃按住状态
///  - timestamp 必须写真实值（CGEvent 的 timestamp 单位是开机后纳秒）
///  - 全局注入只能走 .cghidEventTap（.cgSessionEventTap 对部分游戏无效）
enum KeyPresser {
    static func makeSource() -> CGEventSource? {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return nil }
        // 关掉事件抑制间隔，否则合成事件可能被系统在短时间里丢掉
        src.localEventsSuppressionInterval = 0
        return src
    }

    static func post(vk: CGKeyCode, down: Bool, isRepeat: Bool, source: CGEventSource) {
        guard let ev = CGEvent(keyboardEventSource: source, virtualKey: vk, keyDown: down) else { return }
        ev.timestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        ev.setIntegerValueField(.keyboardEventAutorepeat, value: isRepeat ? 1 : 0)
        ev.post(tap: .cghidEventTap)
    }

    /// 按一次、不发后续事件、过一会儿再松 —— 实测这样能维持「按住」状态。
    /// 中间按系统真实重复频率补发 keyDown（autorepeat=1），模拟物理键盘，避免有些游戏只认重复事件。
    @discardableResult
    static func hold(
        vk: CGKeyCode, seconds: Double, useAutorepeat: Bool,
        canPost: (@MainActor () -> Bool)? = nil
    ) async -> Bool {
        let owner = UUID()
        guard let src = makeSource(), await postDown(vk: vk, owner: owner, isRepeat: false, source: src, canPost: canPost) else {
            return false
        }

        let deadline = Date().addingTimeInterval(seconds)
        var fired = 0
        var lostFocus = false
        if useAutorepeat {
            // 和物理键盘一致：先过系统的首次重复延迟，再按重复间隔补发。
            // 用「下一个目标时间点」推进而不是盲目 sleep，可以自动追上被系统拖慢的节拍。
            let delay = max(NSEvent.keyRepeatDelay, 0.05)
            let interval = max(NSEvent.keyRepeatInterval, 1.0 / 120.0)
            let started = Date()
            while !Task.isCancelled {
                let target = started.addingTimeInterval(delay + Double(fired) * interval)
                // 严格不越过 deadline：宁可少发一次，也不能把 keyUp 拖晚
                guard target < deadline else { break }
                let sleepFor = target.timeIntervalSince(Date())
                if sleepFor > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(sleepFor * 1_000_000_000))
                }
                if Task.isCancelled || Date() >= deadline { break }
                guard await postDown(vk: vk, owner: owner, isRepeat: true, source: src, canPost: canPost) else {
                    lostFocus = true
                    break
                }
                fired += 1
            }
        }
        // 发完最后一次重复事件后，仍保持按下直至原定结束时间。
        let remaining = deadline.timeIntervalSinceNow
        if !lostFocus, !Task.isCancelled, remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }

        // 若停止或休眠路径已经松键，旧任务不能再松开随后启动的同一个键。
        let released = HeldKeys.shared.release(vk, owner: owner, source: src)
        Log.write("hold done vk=\(vk) fired=\(fired) cancelled=\(Task.isCancelled) held=\(HeldKeys.shared.count) systemKeyState=\(CGEventSource.keyState(.combinedSessionState, key: vk) ? "DOWN" : "up")")
        return released && !Task.isCancelled && !lostFocus
    }

    private static func postDown(
        vk: CGKeyCode, owner: UUID, isRepeat: Bool, source: CGEventSource,
        canPost: (@MainActor () -> Bool)?
    ) async -> Bool {
        if let canPost {
            // 在主线程上连续检查焦点并投递，缩短系统切窗与发键之间的时间差。
            return await MainActor.run {
                guard !Task.isCancelled, canPost() else { return false }
                return HeldKeys.shared.postDown(vk, owner: owner, isRepeat: isRepeat, source: source)
            }
        }
        // 命令行自检用信号量等待，不能依赖主线程执行。
        guard !Task.isCancelled else { return false }
        return HeldKeys.shared.postDown(vk, owner: owner, isRepeat: isRepeat, source: source)
    }

    /// keyUp 之前必须停一下。
    ///
    /// 实测证据：如果重复事件之后紧接着（<1ms）发 keyUp，再用 CGEventTap 观察能看到
    /// keyUp 确实进了系统事件流，但接收端 App 的 NSApplication.sendEvent 收不到 ——
    /// 也就是说事件被合成/合并掉了，结果就是「键卡住不松」。
    /// 真键盘永远不会这么快，所以这里补一个真实键盘也有的最小间隔。
    private static let releaseGap: UInt32 = 45_000  // 45ms
    /// 松开要发几次。多余的 keyUp 对系统是空操作（没有对应的 keyDown），
    /// 但只要有一次被合并/丢到别的窗口，前一次就已经把键松开了 —— 这个便宜必须占。
    private static let releaseAttempts = 3

    static func safeRelease(vk: CGKeyCode, source: CGEventSource) {
        for i in 0..<releaseAttempts {
            if i > 0 { usleep(releaseGap) }
            post(vk: vk, down: false, isRepeat: false, source: source)
        }
    }
}

/// 记录当前「我们按下去但还没松开」的键，保证任何退出路径都能补上 keyUp。
final class HeldKeys {
    static let shared = HeldKeys()
    private let lock = NSLock()
    private var held: [CGKeyCode: UUID] = [:]

    func postDown(_ vk: CGKeyCode, owner: UUID, isRepeat: Bool, source: CGEventSource) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if isRepeat {
            guard held[vk] == owner else { return false }
        } else {
            guard held[vk] == nil else { return false }
            held[vk] = owner
        }
        KeyPresser.post(vk: vk, down: true, isRepeat: isRepeat, source: source)
        return true
    }

    func release(_ vk: CGKeyCode, owner: UUID, source: CGEventSource) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard held[vk] == owner else { return false }
        releaseKey(vk, source: source)
        held.removeValue(forKey: vk)
        return true
    }

    /// 幂等。先把键松开，再允许后续任务使用同一个键。
    @discardableResult
    func releaseAll() -> [CGKeyCode] {
        lock.lock(); defer { lock.unlock() }
        guard !held.isEmpty, let source = KeyPresser.makeSource() else { return [] }
        let pending = Array(held.keys)
        for vk in pending { releaseKey(vk, source: source) }
        held.removeAll()
        return pending
    }

    private func releaseKey(_ vk: CGKeyCode, source: CGEventSource) {
        KeyPresser.safeRelease(vk: vk, source: source)
        // 事件发出不代表系统状态已松开。换事件源再补发一次序列。
        if CGEventSource.keyState(.combinedSessionState, key: vk), let fresh = KeyPresser.makeSource() {
            for _ in 0..<3 {
                usleep(45_000)
                KeyPresser.post(vk: vk, down: false, isRepeat: false, source: fresh)
            }
            Log.write("release WARNING vk=\(vk) 仍按下，补发后=\(CGEventSource.keyState(.combinedSessionState, key: vk) ? "DOWN" : "up")")
        }
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return held.count
    }
}
