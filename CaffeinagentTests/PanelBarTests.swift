import XCTest

/// SwiftUI works the bar at the bottom out again only when its `PanelBar`
/// changed, and that closes the submenu the user has open. So the bar
/// must not follow the time or the agents.
final class PanelBarTests: XCTestCase {
    private let now = PanelFixtures.now

    private func input(_ agents: [PanelFixtures.Agent] = [
        .init(id: "claude", name: "Claude Code", state: .working, reason: .reportsBusy, minutes: 12, label: "wiki", cause: .working),
        .init(id: "codex", name: "Codex", minutes: 25),
    ]) -> PanelInput {
        PanelFixtures.input(.working(.one("Claude Code")), agents)
    }

    private func bar(_ input: PanelInput, now: Date) -> PanelBar {
        PanelBar(MenuModel.state(input, now: now), enabled: input.enabled, mode: input.mode)
    }

    func testStaysEqualWhileTheTimeAndTheAgentsChange() {
        let first = input()
        let later = now.addingTimeInterval(3 * 3600)
        XCTAssertNotEqual(MenuModel.state(first, now: now), MenuModel.state(first, now: later), "The durations count on")
        XCTAssertEqual(bar(first, now: now), bar(first, now: later))

        // Another sample: an agent more, another state, folder and clock.
        var second = input([
            .init(id: "claude", name: "Claude Code", state: .waitingForUser, reason: .asksPermission, minutes: 1, label: "site", cause: .waitingForUser),
            .init(id: "codex", name: "Codex", state: .working, reason: .runningCommand(3), minutes: 40, label: "wiki", cause: .working),
            .init(id: "gemini", name: "Gemini CLI", minutes: 300),
        ])
        second.onBattery = false
        second.batteryPercent = 40
        XCTAssertNotEqual(MenuModel.state(first, now: now).groups, MenuModel.state(second, now: now).groups)
        XCTAssertEqual(MenuModel.bar(first), MenuModel.bar(second))
        XCTAssertEqual(bar(first, now: now), bar(second, now: later))
    }

    func testIsTheBarOfTheState() {
        var paused = input()
        paused.pausedUntil = now.addingTimeInterval(3600)
        paused.entitlement = .trial(daysLeft: 9)
        var reachable = input()
        reachable.reachableUntil = now.addingTimeInterval(3600)
        reachable.onBattery = true
        reachable.batteryPercent = 80
        reachable.mode = .always
        for input in [input(), paused, reachable] {
            XCTAssertEqual(MenuModel.bar(input), bar(input, now: now))
        }
    }

    func testChangesWithWhatTheBarShows() {
        let plain = MenuModel.bar(input())

        var mode = input()
        mode.mode = .always
        XCTAssertNotEqual(MenuModel.bar(mode), plain)

        var off = input()
        off.enabled = false
        XCTAssertNotEqual(MenuModel.bar(off), plain)
        XCTAssertTrue(MenuModel.bar(off).reachableActions.isEmpty)

        var paused = input()
        paused.pausedUntil = now.addingTimeInterval(3600)
        XCTAssertNotEqual(MenuModel.bar(paused), plain)
        var pausedLonger = paused
        pausedLonger.pausedUntil = now.addingTimeInterval(2 * 3600)
        XCTAssertNotEqual(MenuModel.bar(pausedLonger), MenuModel.bar(paused), "Another end of the pause")

        var reachable = input()
        reachable.reachableUntil = now.addingTimeInterval(3600)
        XCTAssertNotEqual(MenuModel.bar(reachable), plain)
        var reachableLonger = reachable
        reachableLonger.reachableUntil = now.addingTimeInterval(2 * 3600)
        XCTAssertNotEqual(MenuModel.bar(reachableLonger), MenuModel.bar(reachable), "Another end of \"stay reachable\"")

        var trial = input()
        trial.entitlement = .trial(daysLeft: 9)
        XCTAssertEqual(MenuModel.bar(trial).licenseActions, [.buy, .enterKey])
        XCTAssertNotEqual(MenuModel.bar(trial), plain)
        var withKey = trial
        withKey.hasLicenseKey = true
        XCTAssertNotEqual(MenuModel.bar(withKey), MenuModel.bar(trial), "Whoever has a key is not offered one")

        var onBattery = input()
        onBattery.onBattery = true
        onBattery.batteryPercent = 80
        XCTAssertNotEqual(MenuModel.bar(onBattery), plain, "What \"stay reachable\" costs is in the menu")
    }
}
