import Foundation
import Carbon.HIToolbox

/// Carbon 热键的共享管理器。
///
/// 为什么必须是「一个 handler + 按 ID 分发」：
/// RegisterEventHotKey 只是登记组合键，事件仍然发到 GetApplicationEventTarget()，
/// 由装在同一个 target 上的 handler 处理。如果每个热键各装一个 handler，
/// 按任意一个键时四个 handler 都是候选，而 handler 只看 signature 不看 id，
/// 就会触发错误的预设（或全部触发）。Apple 的标准做法就是单 handler 读 EventHotKeyID 再分发。
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    private static let signature: OSType = 0x484B4559 // 'HKEY'

    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    /// 每次注册分配一个 token。只有「当前注册者」的 deinit 才能注销，
    /// 避免重建热键时旧句柄延迟释放把刚注册的同 ID 热键删掉。
    private var tokens: [UInt32: UUID] = [:]
    private var handlerRef: EventHandlerRef?

    /// 所有 register/unregister/fire 都在主线程，字典无需加锁。
    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            let err = GetEventParameter(event,
                                        EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID),
                                        nil,
                                        MemoryLayout<EventHotKeyID>.size,
                                        nil,
                                        &hkID)
            guard err == noErr else { return err }
            guard hkID.signature == GlobalHotKeyManager.signature else { return OSStatus(eventNotHandledErr) }
            let me = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            let id = hkID.id
            DispatchQueue.main.async { me.fire(id) }
            return noErr
        }, 1, &spec, selfPtr, &handlerRef)
        if status != noErr {
            FileHandle.standardError.write("GlobalHotKey: InstallEventHandler 失败 \(status)\n".data(using: .utf8)!)
        }
    }

    /// 注册/替换一个热键。id 必须全局唯一（预设用 1–4）。
    @discardableResult
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32,
                  token: UUID, action: @escaping () -> Void) -> Bool {
        unregister(id: id)   // 替换同 ID 的旧注册，强制注销
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: GlobalHotKeyManager.signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        actions[id] = action
        tokens[id] = token
        return true
    }

    /// 带 token 的注销：若传入的 token 不是当前注册者，忽略（防止旧句柄误删新热键）。
    /// 不带 token 调用则强制注销（用于 register 替换同 ID）。
    func unregister(id: UInt32, token: UUID? = nil) {
        if let token, tokens[id] != token { return }
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        actions.removeValue(forKey: id)
        tokens.removeValue(forKey: id)
    }

    private func fire(_ id: UInt32) {
        actions[id]?()
    }
}

/// 单个热键的句柄。deinit 自动注销，调用方只需持有它。
final class GlobalHotKey {
    private let id: UInt32
    private let token = UUID()

    init?(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.id = id
        guard GlobalHotKeyManager.shared.register(id: id, keyCode: keyCode,
                                                  modifiers: modifiers,
                                                  token: token, action: action) else {
            return nil
        }
    }

    deinit {
        GlobalHotKeyManager.shared.unregister(id: id, token: token)
    }
}
