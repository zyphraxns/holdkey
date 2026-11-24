import Foundation
import AppKit
import Carbon.HIToolbox

/// 一个全局热键组合。modifiers 用 Carbon 修饰键位，和 RegisterEventHotKey 完全一致。
struct HotKeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    /// 纯主键的可读标签（不含修饰键），例如 "H" / "空格"
    var keyLabel: String

    /// 显示成 "⌥⌘H" 这样的字符串
    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s + keyLabel
    }

    /// 不含 Ctrl 才算安全 —— 原神里 Ctrl 是走/跑切换，修饰键漏进去会误触。
    var containsControl: Bool { modifiers & UInt32(controlKey) != 0 }

    static func optionCommand(_ keyCode: UInt32, label: String) -> HotKeyCombo {
        .init(keyCode: keyCode,
              modifiers: UInt32(optionKey | cmdKey),
              keyLabel: label)
    }
}

/// 固定的 4 个预设槽。id 同时用作热键注册 ID（+1，避开 0）。
struct HoldPreset: Codable, Identifiable, Equatable {
    var id: Int
    var name: String
    var keyID: String
    var seconds: Double
    var hotKey: HotKeyCombo
}

enum PresetDefaults {
    /// 默认全部 ⌥⌘ 开头，不含 Ctrl。
    static let all: [HoldPreset] = [
        .init(id: 0, name: "前进", keyID: "w",     seconds: 30,
              hotKey: .optionCommand(UInt32(kVK_ANSI_H), label: "H")),
        .init(id: 1, name: "左移", keyID: "a",     seconds: 30,
              hotKey: .optionCommand(UInt32(kVK_ANSI_J), label: "J")),
        .init(id: 2, name: "后退", keyID: "s",     seconds: 30,
              hotKey: .optionCommand(UInt32(kVK_ANSI_K), label: "K")),
        .init(id: 3, name: "跳跃", keyID: "space", seconds: 30,
              hotKey: .optionCommand(UInt32(kVK_ANSI_L), label: "L")),
    ]

    /// 常见按键的可读标签。录制热键时用不到全部，但覆盖字母和数字就够用了。
    static func keyLabel(for code: UInt32) -> String {
        if let s = keyMap[code] { return s }
        return "键(code)"
    }

    private static let keyMap: [UInt32: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G",
        0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q",
        0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T",
        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5",
        0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0",
        0x1E: "]", 0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
        0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";", 0x2A: "\\",
        0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".",
        0x30: "Tab", 0x31: "空格", 0x32: "`", 0x33: "Delete", 0x35: "Esc",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
    ]
}

/// 把 NSEvent 的修饰键转成 Carbon 位。
func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var m: UInt32 = 0
    if flags.contains(.control) { m |= UInt32(controlKey) }
    if flags.contains(.option)  { m |= UInt32(optionKey) }
    if flags.contains(.shift)   { m |= UInt32(shiftKey) }
    if flags.contains(.command) { m |= UInt32(cmdKey) }
    return m
}

/// 录制热键用的本地事件监听器容器（SwiftUI @State 不能直接放可变 token 结构）。
final class EventMonitorBox {
    var token: Any?
}
