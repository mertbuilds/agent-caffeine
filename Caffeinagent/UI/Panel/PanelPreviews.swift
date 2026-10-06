#if DEBUG
import SwiftUI

/// A menu over one fixed state, with controls that work.
struct PanelPreview: View {
    let state: PanelState
    var startsExpanded = false
    var startsToggled: Set<String> = []
    @State private var enabled: Bool
    @State private var mode: AwakeMode

    init(state: PanelState, startsExpanded: Bool = false, startsToggled: Set<String> = [], enabled: Bool = true, mode: AwakeMode = .agentWorking) {
        self.state = state
        self.startsExpanded = startsExpanded
        self.startsToggled = startsToggled
        _enabled = State(initialValue: enabled)
        _mode = State(initialValue: mode)
    }

    var body: some View {
        PanelView(
            state: state, enabled: $enabled, mode: $mode, startsExpanded: startsExpanded, startsToggled: startsToggled,
            perform: { _ in }, openPreferences: {}, quit: {}
        )
    }
}

#Preview("Working") { PanelPreview(state: PanelFixtures.working) }
#Preview("Expanded idle list") { PanelPreview(state: PanelFixtures.working, startsExpanded: true) }
#Preview("Grouped sessions") { PanelPreview(state: PanelFixtures.grouped) }
#Preview("Working and waiting") { PanelPreview(state: PanelFixtures.mixed) }
#Preview("Idle groups") { PanelPreview(state: PanelFixtures.idleGroups) }
#Preview("Idle group opened") { PanelPreview(state: PanelFixtures.idleGroups, startsToggled: ["claude"]) }
#Preview("Long session name") { PanelPreview(state: PanelFixtures.longLabel) }
#Preview("Waiting") { PanelPreview(state: PanelFixtures.waiting) }
#Preview("All idle") { PanelPreview(state: PanelFixtures.allIdle) }
#Preview("No agent") { PanelPreview(state: PanelFixtures.noAgent) }
#Preview("Off") { PanelPreview(state: PanelFixtures.off, enabled: false) }
#Preview("Paused") { PanelPreview(state: PanelFixtures.paused) }
#Preview("Paused until tomorrow") { PanelPreview(state: PanelFixtures.pausedUntilTomorrow) }
#Preview("Reachable") { PanelPreview(state: PanelFixtures.reachable) }
#Preview("Reachable, lid closed not set up") { PanelPreview(state: PanelFixtures.reachableNoHelper) }
#Preview("Safety stop") { PanelPreview(state: PanelFixtures.safetyStop) }
#Preview("Too hot") { PanelPreview(state: PanelFixtures.tooHot) }
#Preview("On battery") { PanelPreview(state: PanelFixtures.onBattery) }
#Preview("On battery, near the floor") { PanelPreview(state: PanelFixtures.onBatteryNearFloor) }
#Preview("On battery, stopped") { PanelPreview(state: PanelFixtures.onBatteryStopped) }
#Preview("Lid closed not set up") { PanelPreview(state: PanelFixtures.lidClosedNotSetUp) }
#Preview("Helper switched off") { PanelPreview(state: PanelFixtures.helperSwitchedOff, mode: .always) }
#Preview("Helper gives no answer") { PanelPreview(state: PanelFixtures.helperNotResponding) }
#Preview("Trial ending") { PanelPreview(state: PanelFixtures.trialEnding) }
#Preview("Trial over") { PanelPreview(state: PanelFixtures.trialOver) }

#Preview("Robot poses") {
    HStack(spacing: 16) {
        ForEach(Array([HeroPose.awake(wisps: 2), .reachable, .attentive, .asleep, .paused, .off, .safetyStop(.battery), .safetyStop(.heat), .helperOff].enumerated()), id: \.offset) { _, pose in
            RobotHero(pose: pose)
        }
    }
    .padding()
}
#endif
