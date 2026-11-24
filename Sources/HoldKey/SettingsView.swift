import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var engine: HoldEngine

    var body: some View {
        Form {
            Section("权限") {
                HStack {
                    Image(systemName: engine.hasPostEventAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(engine.hasPostEventAccess ? Color.green : Color.orange)
                    Text(engine.hasPostEventAccess
                         ? "已获得合成按键权限"
                         : "尚未获得权限：现在按键发不出去")
                        .font(.system(size: 12))
                }
                HStack {
                    Button("打开辅助功能设置") { engine.openAccessibilitySettings() }
                    Button("重新检查") { engine.refreshPermissions() }
                }
            }

            Section(header: Text("全局热键")) {
                Toggle("启用预设热键", isOn: $engine.hotKeyEnabled)
                ForEach(0..<engine.presets.count, id: \.self) { i in
                    HStack {
                        Text("\(i + 1). \(engine.presets[i].name)")
                        Spacer()
                        Text(engine.presets[i].hotKey.display)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }
                }
                Text(engine.hotKeyAvailable
                     ? "热键已就绪：在游戏里直接按就能触发，不用切出窗口。"
                     : "部分热键注册失败（可能被别的 App 占用）。请在面板里换一个组合。")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            }

            Section("安全") {
                Text("松键保证：正常结束、手动停止、退出 App、系统休眠、锁屏、断电、kill 信号都会补发 keyUp。")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                Button("立刻释放所有按键") {
                    engine.emergencyRelease(reason: "手动释放")
                }
            }

            Section("关于") {
                Text("HoldKey 0.1 — 四个预设，每个一键按住指定键 N 秒。")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 430)
    }
}
