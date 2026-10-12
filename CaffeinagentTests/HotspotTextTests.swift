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
        XCTAssertEqual(PanelText.hotspotTitle, "Join your iPhone hotspot (Beta)")
        XCTAssertEqual(
            PanelText.hotspotExplained,
            "When Wi-Fi is lost while an agent works, your Mac joins this hotspot. This uses the data and the battery of your phone."
        )
        XCTAssertEqual(
            PanelText.hotspotHopBackExplained,
            "On the hotspot, your Mac looks for the Wi-Fi it lost every 2 minutes, and every 10 minutes on battery with the lid closed. It goes back when the signal is good on 2 looks in a row, and never to an open network or to one that asks for a user name."
        )
    }

    func testWhatTheMacDoesOnTheHotspotIsSaid() {
        XCTAssertEqual(PanelText.hotspotStays, "Your Mac stays on the hotspot until its Wi-Fi comes back or you change the network.")
        XCTAssertEqual(PanelText.hotspotLeaves, "If you leave the hotspot, your Mac does not join it again by itself.")
    }

    func testTheLimitIsSaidAndTheAdviceOnlyWhereMacOSHasTheChoice() {
        XCTAssertEqual(
            PanelText.hotspotLimit(offersAutomatic: true),
            "Your iPhone shows its hotspot only for a short time. If your Mac does not find it, set Ask to join hotspots to Automatic in Wi-Fi settings."
        )
        XCTAssertEqual(
            PanelText.hotspotLimit(offersAutomatic: false),
            "Your iPhone shows its hotspot only for a short time, so your Mac does not always find it."
        )
        XCTAssertEqual(PanelText.hotspotAutoJoin(.automatic), "Ask to join hotspots is set to Automatic")
        XCTAssertEqual(PanelText.hotspotAutoJoin(.notAutomatic), "Ask to join hotspots is not set to Automatic")
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
        XCTAssertEqual(PanelText.hotspotSaveNote(.incomplete), "Type the name and the password of your hotspot")
        XCTAssertEqual(PanelText.hotspotSaveNote(.keychainFailed), "Agent Caffeine could not save the password in your Keychain")
        XCTAssertEqual(PanelText.hotspotSaveNote(.saved(.allowed)), "Saved. Agent Caffeine can see the names of Wi-Fi networks.")
        XCTAssertEqual(PanelText.hotspotSaveNote(.saved(.notNeeded)), "Saved")
        XCTAssertEqual(
            PanelText.hotspotSaveNote(.saved(.notAsked)),
            "Saved. Allow Location when macOS asks, so Agent Caffeine can find the hotspot by its name."
        )
        XCTAssertEqual(PanelText.hotspotSaveNote(.saved(.denied)), "Saved. Location permission is off, so Agent Caffeine cannot find the hotspot.")
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
            PanelText.hotspotOpenWiFi, PanelText.hotspotStays, PanelText.hotspotLeaves, PanelText.hotspotHopBack, PanelText.hotspotHopBackExplained, PanelText.hotspotForgets,
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
            XCTAssertEqual(line.first?.isUppercase ?? false || line.hasPrefix("macOS"), true, line)
        }
    }
}
