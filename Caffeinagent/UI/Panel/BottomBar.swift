import AppKit
import SwiftUI

/// The quiet controls: the mode, the gear menu, the timer menu and the
/// switch. While agent caffeine is paused, the end of the pause stands in
/// place of the mode, and while the Mac stays reachable, the end of that.
///
/// SwiftUI closes the open submenu of a `Menu` when it works the menu out
/// again. So the bar is worked out again only when what it shows changed:
/// put it in the menu with `.equatable()`.
struct BottomBar: View, Equatable {
    let bar: PanelBar
    @Binding var enabled: Bool
    @Binding var mode: AwakeMode
    let perform: (PanelAction) -> Void
    let openPreferences: () -> Void
    let quit: () -> Void

    /// The bindings and the actions reach the same objects whenever they
    /// were made, so the values alone tell two bars apart.
    static func == (a: BottomBar, b: BottomBar) -> Bool {
        a.bar == b.bar
    }

    var body: some View {
        HStack(spacing: 8) {
            if let pausedLabel = bar.pausedLabel {
                timed(pausedLabel, end: PanelText.resume, action: .resume)
            } else if let reachableLabel = bar.reachableLabel {
                timed(reachableLabel, end: PanelText.stop, action: .stopReachable)
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
                if bar.pausedLabel != nil {
                    Button(PanelAction.resume.title) { perform(.resume) }
                } else if enabled {
                    Menu(PanelText.pauseMenu) { pauseChoices }
                }
                if enabled, !bar.reachableActions.isEmpty {
                    Menu(PanelText.reachableMenu) { reachableChoices }
                }
                ForEach(bar.licenseActions, id: \.title) { action in
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

            // One click from the switch: a pause, and its opposite. Off
            // and paused have nothing to pause, and while the Mac stays
            // reachable the bar needs the room for the time and "Stop".
            if enabled, bar.pausedLabel == nil, bar.reachableLabel == nil {
                Menu {
                    Section { pauseChoices }
                    if !bar.reachableActions.isEmpty {
                        Section { reachableChoices }
                    }
                } label: {
                    Label(PanelText.timerMenu, systemImage: "timer")
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

    /// Until when, and the way out.
    @ViewBuilder
    private func timed(_ label: String, end: String, action: PanelAction) -> some View {
        Text(label)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .layoutPriority(1)
        Button(end) { perform(action) }
            .buttonStyle(.link)
            .frame(minHeight: PanelMetrics.controlHeight)
    }

    private var pauseChoices: some View {
        ForEach(PauseChoice.allCases, id: \.self) { choice in
            Button(PanelAction.pause(choice).title) { perform(.pause(choice)) }
        }
    }

    /// With what it costs on battery, as a line that is no choice.
    @ViewBuilder
    private var reachableChoices: some View {
        if bar.reachableLabel != nil {
            Button(PanelAction.stopReachable.title) { perform(.stopReachable) }
        }
        ForEach(bar.reachableActions, id: \.title) { action in
            Button(action.title) { perform(action) }
        }
        if let reachableCost = bar.reachableCost {
            Text(reachableCost)
        }
    }
}
