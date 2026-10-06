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
                Picker(PanelText.modePicker, selection: $mode) {
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
            .accessibilityLabel(PanelText.modePicker)
            .accessibilityValue(mode.title)

            Spacer(minLength: 8)

            Menu {
                Button(PanelText.preferences, action: openPreferences)
                ForEach(licenseActions, id: \.title) { action in
                    Button(action == .buy ? PanelText.buyInMenu : action.title) { perform(action) }
                }
                Divider()
                Button(PanelText.quit, action: quit)
            } label: {
                Label(PanelText.gearMenu, systemImage: "gearshape")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(.secondary)
            .fixedSize()
            .frame(minWidth: PanelMetrics.controlHeight, minHeight: PanelMetrics.controlHeight)

            Toggle(PanelText.mainSwitch, isOn: $enabled)
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
