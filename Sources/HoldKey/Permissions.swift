import Foundation
import ApplicationServices
import CoreGraphics

/// 判断「能不能把合成按键送进系统」。
///
/// 结论来自本机实测：
///   - 一个 ad-hoc / 未经授权的 .app 进程，CGPreflightPostEventAccess() 返回 false，
///     而且 CGEvent.post 调用会静默失败 —— 不报错、不抛异常，就是没反应。
///     这是最容易踩的坑：以为代码写错了，其实是没授权。
///   - 所以必须在 UI 上把状态显式和可操作地暴露出来。
enum Permissions {

    /// 是否已获得「合成事件」权限（对应 系统设置 → 隐私与安全性 → 辅助功能）
    static var canPostEvents: Bool {
        CGPreflightPostEventAccess()
    }

    /// 兼容旧判断：Accessibility 授权状态
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static var allGood: Bool { canPostEvents || isAccessibilityTrusted }

    /// 触发系统的授权弹窗（只会弹一次，之后需要用户自己到系统设置里勾）
    @discardableResult
    static func requestPostEventAccess() -> Bool {
        CGRequestPostEventAccess()
    }

    @discardableResult
    static func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 打开 系统设置 → 隐私与安全性 → 辅助功能
    static func openAccessibilityPane() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        ]
        for s in urls {
            if let u = URL(string: s), NSWorkspaceHelper.canOpen(u) {
                NSWorkspaceHelper.open(u)
                return
            }
        }
    }
}

import AppKit
enum NSWorkspaceHelper {
    static func canOpen(_ url: URL) -> Bool { true }
    static func open(_ url: URL) { NSWorkspace.shared.open(url) }
}
