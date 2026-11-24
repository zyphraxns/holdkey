import SwiftUI
import AppKit
import Carbon.HIToolbox

struct MenuContent: View {
    @ObservedObject var engine: HoldEngine
    @Environment(\.openWindow) private var openWindow
    @State private var secondsText: String = ""
    @State private var recordingID: Int? = nil
    @State private var recordHint: String = ""
    @State private var monitor = EventMonitorBox()

    private var preset: HoldPreset { engine.selectedPreset }

    private var secondsBinding: Binding<Double> {
        Binding(
            get: { engine.selectedPreset.seconds },
            set: { engine.updatePreset(id: engine.selectedPresetID, seconds: $0) }
        )
    }

    private var keyBinding: Binding<String> {
        Binding(
            get: { engine.selectedPreset.keyID },
            set: { engine.updatePreset(id: engine.selectedPresetID, keyID: $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── 状态行 ─────────────────────────────
            HStack(spacing: 8) {
                Circle()
                    .fill(engine.isRunning ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 8, height: 8)
                Text(engine.isRunning
                     ? "按住 \(engine.activePresetName) · 剩 \(Int(engine.remaining.rounded())) 秒"
                     : "待命")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(engine.isRunning ? .primary : .secondary)
                Spacer()
            }

            if !engine.permissionsOK {
                PermissionBanner(engine: engine)
            }

            Divider()

            // ── 预设选择 ───────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                Text("预设（每个都有自己的热键）").font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Picker("", selection: Binding(
                        get: { engine.selectedPresetID },
                        set: { engine.selectPreset(id: $0) }
                    )) {
                        ForEach(engine.presets) { p in
                            Text("\(p.id + 1). \(p.name)  \(p.hotKey.display)").tag(p.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(engine.isRunning)
                    TextField("名称", text: Binding(
                        get: { engine.selectedPreset.name },
                        set: { engine.updatePreset(id: engine.selectedPresetID, name: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 76)
                    .font(.system(size: 12))
                    .disabled(engine.isRunning)
                }
            }

            // ── 时长输入 ───────────────────────────
            HStack(spacing: 8) {
                Text("按住").font(.system(size: 12))
                TextField("30", text: $secondsText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 13, design: .monospaced))
                    .onSubmit { commitText() }
                    .onChange(of: secondsText) { _, _ in commitText() }
                Text("秒").font(.system(size: 12))
                Spacer()
                Stepper("", value: secondsBinding, in: 1...1800, step: 5)
                    .labelsHidden()
                    .onChange(of: preset.seconds) { _, newValue in
                        let t = fmt(newValue)
                        if t != secondsText { secondsText = t }
                    }
            }

            // ── 按键选择 ───────────────────────────
            HStack(spacing: 8) {
                Text("按住哪个键").font(.system(size: 12))
                Spacer()
                Picker("", selection: keyBinding) {
                    ForEach(HoldableKey.all) { k in
                        Text(k.label).tag(k.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 96)
                .disabled(engine.isRunning)
            }

            // ── 热键录制 ───────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("热键").font(.system(size: 12))
                    Text(preset.hotKey.display)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Spacer()
                    Button(recordingID == preset.id ? "取消" : "录制") {
                        if recordingID == preset.id { stopRecording() } else { startRecording() }
                    }
                    .font(.system(size: 11))
                    .controlSize(.small)
                    .disabled(engine.isRunning)
                }
                if recordingID == preset.id {
                    Text("按下新组合键（例如 ⌥⌘H）；Esc 取消。不要用 Ctrl，原神里它是走/跑切换。")
                        .font(.system(size: 10))
                        .foregroundStyle(recordHint.isEmpty ? Color.secondary : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !recordHint.isEmpty {
                    Text(recordHint)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.orange)
                }
            }

            // ── 开火按钮 ───────────────────────────
            Button {
                if engine.isRunning { engine.stop() } else { engine.fire() }
            } label: {
                HStack {
                    Image(systemName: engine.isRunning ? "stop.fill" : "play.fill")
                    Text(engine.isRunning
                         ? "停止"
                         : "开始按住 \(HoldableKey.byID(preset.keyID).label)")
                }
                .frame(maxWidth: .infinity)
                .font(.system(size: 13, weight: .semibold))
                .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.isRunning ? Color.red : Color.accentColor)
            .keyboardShortcut(.return, modifiers: [])

            // ── 说明 & 提示 ────────────────────────
            Text(engine.isRunning
                 ? "保持游戏在前台即可，别切窗口。"
                 : "选好预设，按它的热键就能直接开始；也可以点上面的按钮。开始后保持游戏在前台。")
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !engine.lastMessage.isEmpty {
                Text(engine.lastMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // ── 底部 ──────────────────────────────
            HStack(spacing: 10) {
                Toggle(isOn: $engine.useAutorepeat) {
                    Text("模拟按键重复").font(.system(size: 11))
                }
                .toggleStyle(.checkbox)
                .help("有些游戏只认重复的按键事件。如果角色没动，试着切换这个。")
                Spacer()
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("设置")
                Button("退出") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { secondsText = fmt(preset.seconds) }
        .onChange(of: engine.selectedPresetID) { _, _ in
            secondsText = fmt(engine.selectedPreset.seconds)
            recordHint = ""
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        recordHint = ""
        recordingID = engine.selectedPresetID
        NSApp.activate(ignoringOtherApps: true)
        stopMonitor()
        let id = engine.selectedPresetID
        monitor.token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event -> NSEvent? in
            let code = UInt32(event.keyCode)
            if code == UInt32(kVK_Escape) {
                DispatchQueue.main.async { self.stopRecording() }
                return nil
            }
            let mods = carbonModifiers(from: event.modifierFlags)
            guard mods != 0 else {
                DispatchQueue.main.async { self.recordHint = "请带修饰键，例如 ⌥⌘H" }
                return nil
            }
            let combo = HotKeyCombo(keyCode: code, modifiers: mods,
                                    keyLabel: PresetDefaults.keyLabel(for: code))
            if combo.containsControl {
                DispatchQueue.main.async { self.recordHint = "别用 Ctrl，原神里它是走/跑切换。请换一个组合。" }
                return nil
            }
            DispatchQueue.main.async {
                self.engine.updatePreset(id: id, hotKey: combo)
                self.recordHint = "已录制 \(combo.display)"
                self.stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        recordingID = nil
        stopMonitor()
    }

    private func stopMonitor() {
        if let token = monitor.token {
            NSEvent.removeMonitor(token)
            monitor.token = nil
        }
    }

    private func commitText() {
        let cleaned = secondsText.replacingOccurrences(of: ",", with: ".")
        if let v = Double(cleaned), v > 0, v <= 1800 {
            if abs(v - preset.seconds) > 0.0001 {
                engine.updatePreset(id: engine.selectedPresetID, seconds: v)
            }
        }
    }

    private func fmt(_ s: Double) -> String {
        s == s.rounded() ? "\(Int(s))" : String(format: "%.1f", s)
    }
}

/// 没有辅助功能权限时，这是整个 App 里最重要的一块 UI ——
/// 因为缺权限时 CGEvent 会静默失败，用户只会看到「点了没反应」。
struct PermissionBanner: View {
    @ObservedObject var engine: HoldEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
                    .font(.system(size: 11))
                Text("还没有按键权限，现在点了不会有反应")
                    .font(.system(size: 11, weight: .semibold))
            }
            Text("系统设置 → 隐私与安全性 → 辅助功能，勾上 HoldKey。")
                .font(.system(size: 10))
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("打开设置") { Permissions.openAccessibilityPane() }
                    .font(.system(size: 11))
                    .controlSize(.small)
                Button("我已勾上，重新检查") { engine.refreshPermissions() }
                    .font(.system(size: 11))
                    .controlSize(.small)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}
