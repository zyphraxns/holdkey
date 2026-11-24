import Foundation

/// 极简日志：写文件而不是 print，因为在 .app 里 stdout 不可见。
///
/// 注意一个实测坑：从终端直接启动 .app 里的二进制时，进程会继承终端的沙箱限制，
/// 这时 ~/Library/Logs 是不可写的 —— 写日志会静默失败，排查问题时反而误导。
/// 所以这里带一层降级：主路径失败就写到临时目录，至少诊断信息不会凭空消失。
enum Log {
    static let preferredPath = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Logs/HoldKey.log")

    static let fallbackPath = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("HoldKey.log")

    private static let queue = DispatchQueue(label: "holdkey.log")
    /// 一旦降级过就一直用降级路径，避免日志被劈成两半
    private static var activePath: URL = preferredPath

    static func write(_ message: String) {
        queue.async {
            let line = format(message)
            guard let data = line.data(using: .utf8) else { return }
            if append(data, to: activePath) { return }
            if activePath == preferredPath {
                activePath = fallbackPath
                _ = append(data, to: fallbackPath)
            }
        }
    }

    private static func format(_ message: String) -> String {
        let ts = ISO8601DateFormatter().string(from: Date())
        return "[\(ts)] [pid \(ProcessInfo.processInfo.processIdentifier)] \(message)\n"
    }

    private static func append(_ data: Data, to url: URL) -> Bool {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            guard fm.createFile(atPath: url.path, contents: nil) else { return false }
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return false }
        defer { try? handle.close() }
        guard (try? handle.seekToEnd()) != nil else { return false }
        do {
            try handle.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }
}
