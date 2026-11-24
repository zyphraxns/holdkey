import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var engine: HoldEngine

    var body: some View {
        Form {
            Section(L10n.string("section.permissions")) {
                HStack {
                    Image(systemName: engine.hasPostEventAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(engine.hasPostEventAccess ? Color.green : Color.orange)
                    Text(engine.hasPostEventAccess
                         ? L10n.string("perm.granted")
                         : L10n.string("perm.missing"))
                        .font(.system(size: 12))
                }
                HStack {
                    Button(L10n.string("button.openAccessibility")) { engine.openAccessibilitySettings() }
                    Button(L10n.string("button.recheck")) { engine.refreshPermissions() }
                }
            }

            Section(header: Text(L10n.string("section.hotkeys"))) {
                Toggle(L10n.string("toggle.hotkeys"), isOn: $engine.hotKeyEnabled)
                ForEach(0..<engine.presets.count, id: \.self) { i in
                    HStack {
                        Text("\(i + 1). \(engine.presets[i].name)")
                        Spacer()
                        Text(engine.presets[i].hotKey.display)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }
                }
                Text(engine.hotKeyAvailable
                     ? L10n.string("hotkey.ready")
                     : L10n.string("hotkey.partial"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            }

            Section(L10n.string("section.safety")) {
                Text(L10n.string("safety.note"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                Button(L10n.string("button.releaseAll")) {
                    engine.emergencyRelease(reason: "manualRelease")
                }
            }

            Section(L10n.string("section.about")) {
                Text(L10n.string("about.note"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 430)
    }
}
