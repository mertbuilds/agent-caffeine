import AppKit
import SwiftUI

/// The quiet controls: the mode, the gear menu, the pause and the switch.
/// While agent caffeine is paused, the end of the pause stands in place of
/// the mode.
struct BottomBar: View {
    @Binding var enabled: Bool
    @Binding var mode: AwakeMode
    var pausedLabel: String?
    let licenseActions: [PanelAction]
    let perform: (PanelAction) -> Void
    let openPreferences: () -> Void
    let quit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let pausedLabel {
                Text(pausedLabel)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button(PanelText.resume) { perform(.resume) }
                    .buttonStyle(.link)
                    .frame(minHeight: PanelMetrics.controlHeight)
            } else {
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
            }

            Spacer(minLength: 8)

            Menu {
                Button(PanelText.preferences, action: openPreferences)
                if pausedLabel != nil {
                    Button(PanelAction.resume.title) { perform(.resume) }
                } else if enabled {
                    Menu(PanelText.pauseMenu) { pauseChoices }
                }
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

            // One click from the switch. Off and paused have nothing to pause.
            if enabled, pausedLabel == nil {
                Menu {
                    pauseChoices
                } label: {
                    Label(PanelText.pauseMenu, systemImage: "pause.circle")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .tint(.secondary)
                .fixedSize()
                .frame(minWidth: PanelMetrics.controlHeight, minHeight: PanelMetrics.controlHeight)
            }

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

    private var pauseChoices: some View {
        ForEach(PauseChoice.allCases, id: \.self) { choice in
            Button(PanelAction.pause(choice).title) { perform(.pause(choice)) }
        }
    }
}
