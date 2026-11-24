import Foundation

/// UI 本地化便捷入口。走 Bundle.main 的 Localizable.strings，
/// 语言随系统首选语言自动切换（en → 英文，zh-Hans/zh-Hant → 简体，其它回退英文）。
/// 仅用于用户可见字符串；日志、stderr、self-test 诊断串保持中文原样。
enum L10n {
    static func string(_ key: String, _ args: CVarArg...) -> String {
        let fmt = NSLocalizedString(key, bundle: .main, comment: "")
        return withVaList(args) { NSString(format: fmt, arguments: $0) as String }
    }
}
