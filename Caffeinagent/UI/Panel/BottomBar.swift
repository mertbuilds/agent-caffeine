import AppKit
import SwiftUI

/// The quiet controls: the mode, the gear menu, and the switch.
struct BottomBar: View {
    @Binding var enabled: Bool
    @Binding var mode: AwakeMode
    let licenseActions: [PanelAction]
    let perform: (PanelAction) -> Void
    let openPreferences: () -> Void
    let quit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Keep the Mac awake", selection: $mode) {
                    ForEach(AwakeMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Text(mode.shortTitle)
            }
            .menuStyle(.borderlessButton)
            .tint(.secondary)
            .fixedSize()
            .frame(minHeight: PanelMetrics.controlHeight)
            .accessibilityLabel("Keep the Mac awake")
            .accessibilityValue(mode.title)

            Spacer(minLength: 8)

            Menu {
                Button("Preferences…", action: openPreferences)
                ForEach(licenseActions, id: \.title) { action in
                    Button(action == .buy ? "Buy agent caffeine for $9" : action.title) { perform(action) }
                }
                Divider()
                Button("Quit agent caffeine", action: quit)
            } label: {
                Label("Preferences and more", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(.secondary)
            .fixedSize()
            .frame(minWidth: PanelMetrics.controlHeight, minHeight: PanelMetrics.controlHeight)

            Toggle("agent caffeine", isOn: $enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(.brand)
                .frame(minHeight: PanelMetrics.controlHeight)
        }
        .padding(.horizontal, PanelMetrics.gutter)
        .padding(.vertical, 8)
    }
}
