import XCTest

/// The words of "Join your iPhone hotspot" in Settings and in the menu.
final class HotspotTextTests: XCTestCase {
    private let now = JobTime.date("2026-10-10 14:30")
    private let locale = Locale(identifier: "en_GB")
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func at(_ text: String) -> Date { JobTime.date(text) }

    /// On and set up.
    private func view(_ state: HotspotHop.State, permission: LocationPermission = .allowed) -> HotspotView {
        var view = HotspotView()
        view.settings.on = true
        view.settings.name = HopMac.hotspot
        view.settings.passwordSaved = true
        view.state = state
        view.permission = permission
        return view
    }

    private func status(_ state: HotspotHop.State, permission: LocationPermission = .allowed) -> String? {
        PanelText.hotspotStatus(view(state, permission: permission), now: now, calendar: calendar, locale: locale)?.text
    }

    // MARK: Settings

    func testTheSectionSaysWhatItDoesAndWhatItCosts() {
        XCTAssertEqual(PanelText.hotspotTitle, "iPhone hotspot (Beta)")
        XCTAssertEqual(PanelText.hotspotExplained, "Uses the data and battery of your phone")
        XCTAssertEqual(
            PanelText.hotspotHopBackExplained,
            "Your Mac looks for the lost Wi-Fi every 2 minutes, and every 10 minutes on battery with the lid closed. It goes back after a good signal 2 times in a row. It never goes to an open network or to one that asks for a user name. This works only when Agent Caffeine joined the hotspot."
        )
    }

    func testWhatTheMacDoesOnTheHotspotIsSaid() {
        XCTAssertEqual(
            PanelText.hotspotInfo,
            "Only while an agent works. Your Mac stays on the hotspot until you change the network or it goes back to your Wi-Fi. If you leave the hotspot, your Mac does not join it again by itself. When you switch this off, Agent Caffeine forgets the name and the password."
        )
    }

    func testTheLimitIsSaidAndTheAdviceOnlyWhereMacOSHasTheChoice() {
        XCTAssertEqual(
            PanelText.hotspotLimit(offersAutomatic: true),
            "Your iPhone shows its hotspot only for a short time. With Automatic, your Mac finds it more often."
        )
        XCTAssertEqual(PanelText.hotspotLimit(offersAutomatic: false), "Your iPhone shows its hotspot only for a short time")
        XCTAssertEqual(PanelText.hotspotAutoJoin(.automatic), "Automatic")
        XCTAssertEqual(PanelText.hotspotAutoJoin(.notAutomatic), "Not Automatic")
    }

    func testTheStatusLineSaysTheLastResult() {
        let time = at("2026-10-10 14:02")
        XCTAssertNil(status(.idle))
        XCTAssertEqual(status(.waiting), "Wi-Fi is lost. Your Mac looks for the hotspot in a moment.")
        XCTAssertEqual(status(.scanning), "Looking for the hotspot")
        XCTAssertEqual(status(.joined(at: time)), "Joined at 14:02")
        XCTAssertEqual(status(.notFound(at: time)), "Did not find the hotspot at 14:02")
        XCTAssertEqual(status(.hoppedBack(at: time)), "Went back to your Wi-Fi at 14:02")
        XCTAssertEqual(status(.failed(.wrongPassword, at: time)), "The hotspot refused the password at 14:02. Save the password again.")
        XCTAssertEqual(status(.failed(.wifiOff, at: time)), "Wi-Fi was off at 14:02")
        XCTAssertEqual(status(.failed(.noWiFi, at: time)), "This Mac has no Wi-Fi")
        XCTAssertEqual(status(.failed(.noPassword, at: time)), "The password was not in your Keychain at 14:02. Save it again.")
        XCTAssertEqual(status(.failed(.keychainLocked, at: time)), "Your Keychain was locked at 14:02, so your Mac did not join the hotspot")
        XCTAssertEqual(status(.failed(.timeout, at: time)), "macOS gave no answer at 14:02")
        XCTAssertEqual(status(.failed(.other, at: time)), "Could not join the hotspot at 14:02")
        XCTAssertEqual(status(.failed(.notSecure, at: time)), "A network with this name is open, so your Mac did not join it")
        XCTAssertEqual(status(.joined(at: at("2026-10-09 23:10"))), "Joined at Oct 9, 23:10", "Another day has its date")
        let american = PanelText.hotspotStatus(view(.joined(at: time)), now: now, calendar: calendar, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(american?.text.replacingOccurrences(of: "\u{202F}", with: " "), "Joined at 2:02 PM")
    }

    func testAPermissionThatIsOffComesFirstAndHasTheButton() {
        let line = HotspotStatusLine(text: "Location permission is off: open Privacy settings", opensPrivacy: true)
        let time = at("2026-10-10 14:02")
        for state in [HotspotHop.State.idle, .joined(at: time), .failed(.noPermission, at: time), .notFound(at: time)] {
            XCTAssertEqual(PanelText.hotspotStatus(view(state, permission: .denied), now: now, calendar: calendar, locale: locale), line)
        }
        XCTAssertEqual(PanelText.hotspotStatus(view(.failed(.noPermission, at: time)), now: now, calendar: calendar, locale: locale), line)
        XCTAssertEqual(PanelText.hotspotStatus(view(.notFound(at: time)), now: now, calendar: calendar, locale: locale)?.opensPrivacy, false)
    }

    func testNoStatusWhileTheFeatureIsOffOrNotSetUp() {
        var off = view(.joined(at: now))
        off.settings.on = false
        XCTAssertNil(PanelText.hotspotStatus(off, now: now))
        var noPassword = view(.notFound(at: now), permission: .denied)
        noPassword.settings.passwordSaved = false
        XCTAssertNil(PanelText.hotspotStatus(noPassword, now: now))
    }

    func testTheLineNextToSave() {
        XCTAssertEqual(PanelText.hotspotSaveNote(.incomplete), "Type the name and the password")
        XCTAssertEqual(PanelText.hotspotSaveNote(.keychainFailed), "Could not save the password in your Keychain")
        XCTAssertEqual(PanelText.hotspotSaveNote(.saved(.allowed)), "Saved")
        XCTAssertEqual(PanelText.hotspotSaveNote(.saved(.notNeeded)), "Saved")
        XCTAssertEqual(PanelText.hotspotSaveNote(.saved(.notAsked)), "Saved. Allow Location when macOS asks.")
        XCTAssertEqual(PanelText.hotspotSaveNote(.saved(.denied)), "Saved, but Location is off, so your Mac cannot find the hotspot.")
        XCTAssertEqual(PanelText.hotspotSaveNote(.removeFailed), "Agent Caffeine could not remove the password from your Keychain. Try again.")
    }

    // MARK: Menu

    func testTheQuietLineWhileTheMacIsOnTheHotspot() {
        var input = PanelInput(decision: HoldDecision(hold: false, lidClosedFlag: false, headline: .noAgents, perAgent: []))
        input.calendar = calendar
        input.locale = locale
        XCTAssertNil(MenuModel.state(input, now: now).hotspotLine)
        input.hotspotSince = at("2026-10-10 14:02")
        XCTAssertEqual(MenuModel.state(input, now: now).hotspotLine, "On your iPhone hotspot since 14:02")
        XCTAssertEqual(PanelFixtures.onHotspot.hotspotLine, "On your iPhone hotspot since 06:01")
        XCTAssertEqual(PanelFixtures.onHotspot.pose, .awake(wisps: 2), "The headline stays the one of the agent")
        XCTAssertNil(PanelFixtures.onHotspot.attention)
        XCTAssertTrue(PanelFixtures.all.filter { $0.name != "on-hotspot" }.allSatisfy { $0.state.hotspotLine == nil })
    }

    func testTheLineIsThereOnlyWhileTheMacIsOnlineOnTheHotspot() {
        let time = at("2026-10-10 14:02")
        XCTAssertEqual(view(.joined(at: time)).onHotspotSince, time)
        var offline = view(.joined(at: time))
        offline.online = false
        XCTAssertNil(offline.onHotspotSince, "Joined, and the phone gives no path yet")
        var off = view(.joined(at: time))
        off.settings.on = false
        XCTAssertNil(off.onHotspotSince)
        XCTAssertNil(view(.notFound(at: time)).onHotspotSince)
        XCTAssertNil(view(.hoppedBack(at: time)).onHotspotSince)
    }

    // MARK: Style and privacy

    /// Every line of the feature: no name of a network, no password, no
    /// em dash, and no short form of a unit of time.
    func testNoLineNamesANetworkOrBreaksTheStyle() {
        let time = at("2026-10-10 14:02")
        let states: [HotspotHop.State] = [.idle, .waiting, .scanning, .joined(at: time), .notFound(at: time), .hoppedBack(at: time)]
            + HopFailure.allCases.map { .failed($0, at: time) }
        var lines = [
            PanelText.hotspotTitle, PanelText.hotspotSwitch, PanelText.hotspotExplained, PanelText.hotspotName, PanelText.hotspotNamePrompt,
            PanelText.hotspotPassword, PanelText.hotspotPasswordSaved, PanelText.hotspotSave, PanelText.hotspotOpenPrivacy,
            PanelText.hotspotOpenWiFi, PanelText.hotspotInfo, PanelText.hotspotHopBack, PanelText.hotspotHopBackExplained, PanelText.hotspotAutoJoinTitle,
            PanelText.hotspotLimit(offersAutomatic: true), PanelText.hotspotLimit(offersAutomatic: false),
            PanelText.hotspotAutoJoin(.automatic), PanelText.hotspotAutoJoin(.notAutomatic),
            PanelText.hotspotRemoveStep(saved: true), PanelText.hotspotRemoveStep(saved: false), PanelText.hotspotRemoveHelp,
            PanelText.onHotspotSince(time, calendar: calendar, locale: locale),
        ]
        lines += states.compactMap { status($0) }
        lines += [HotspotSaveNote.incomplete, .keychainFailed, .removeFailed, .saved(.allowed), .saved(.notAsked), .saved(.denied), .saved(.notNeeded)]
            .map(PanelText.hotspotSaveNote)
        XCTAssertGreaterThan(lines.count, 35)
        for line in lines {
            XCTAssertFalse(line.contains("Mert"), line)
            XCTAssertFalse(line.contains(HopMac.password), line)
            XCTAssertFalse(line.contains("\u{2014}"), line)
            XCTAssertFalse(line.contains("**"), line)
            XCTAssertNil(line.range(of: #"\d+ ?(min|sec|s|m|h|hr)\b"#, options: .regularExpression), line)
            XCTAssertFalse(line.localizedCaseInsensitiveContains("agent caffeine") && !line.contains("Agent Caffeine"), line)
            XCTAssertEqual(line.first?.isUppercase ?? false || line.hasPrefix("macOS") || line.hasPrefix("iPhone"), true, line)
        }
    }
}
