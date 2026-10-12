import XCTest

/// "Join your iPhone hotspot": `HotspotHop` with `HotspotJob`, against a
/// fake air and a clock the test moves. No test reaches the Wi-Fi.
final class HotspotHopTests: XCTestCase {
    private func joined(_ state: HotspotHop.State) -> Bool {
        if case .joined = state { return true }
        return false
    }

    // MARK: When it joins

    func testNothingIsJoinedWhileTheMacHasAPath() {
        var mac = HopMac()
        mac.run(seconds: 600)
        XCTAssertEqual(mac.state, .idle)
        XCTAssertEqual(mac.wifi.scans, [], "No scan while online")
        XCTAssertEqual(mac.wifi.joins, [])
        XCTAssertTrue(mac.actions.allSatisfy { $0 == .look })
    }

    func testTheLostTimeComesBeforeTheFirstTry() {
        var mac = HopMac()
        mac.run(seconds: 10)
        mac.loseWiFi()
        // The first sample without a path starts the count at zero.
        mac.run(seconds: 14)
        XCTAssertEqual(mac.state, .waiting)
        XCTAssertEqual(mac.wifi.scans, [])
        // A path for one sample ends the count: a short break joins nothing.
        mac.input.online = true
        mac.sample()
        mac.input.online = false
        mac.run(seconds: 14)
        XCTAssertEqual(mac.state, .waiting)
        XCTAssertEqual(mac.wifi.joins, [])
        mac.run(seconds: 4)
        XCTAssertTrue(joined(mac.state))
        XCTAssertEqual(mac.wifi.joins.count, 1)
    }

    func testAFoundHotspotIsJoinedWithTheSavedPassword() {
        var mac = HopMac()
        mac.run(seconds: 10)
        mac.loseWiFi()
        mac.run(seconds: 20)
        XCTAssertEqual(mac.wifi.scans, [HopMac.hotspot])
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot])
        XCTAssertEqual(mac.wifi.joinPasswords, [HopMac.password])
        XCTAssertEqual(mac.wifi.current, HopMac.hotspot)
        guard case .joined(let at) = mac.state else { return XCTFail("\(mac.state.code)") }
        XCTAssertEqual(at.timeIntervalSince(HopMac.start), 28, "10 seconds online, the lost time, and the sample that tried")
        XCTAssertTrue(mac.input.online)
        // Online on the hotspot, nothing is tried again.
        mac.run(seconds: 100)
        XCTAssertEqual(mac.wifi.joins.count, 1)
    }

    func testAPhoneThatDoesNotShowItsHotspotIsTriedAgainOnTheSchedule() {
        var mac = HopMac()
        mac.wifi.air = []
        mac.loseWiFi()
        mac.run(seconds: 300)
        guard case .notFound = mac.state else { return XCTFail("\(mac.state.code)") }
        XCTAssertEqual(mac.wifi.joins, [], "Nothing to join")
        let waits = zip(mac.tryTimes, mac.tryTimes.dropFirst()).map { $1 - $0 }
        XCTAssertEqual(Array(waits.prefix(6)), [10, 20, 40, 60, 60, 60])
        // The phone comes on the air: the next try joins it.
        mac.wifi.air = [HopMac.hotspot]
        mac.run(seconds: 62)
        XCTAssertTrue(joined(mac.state))
    }

    func testTheScheduleStartsAgainAfterTheWayCameBack() {
        var mac = HopMac()
        mac.wifi.air = []
        mac.loseWiFi()
        mac.run(seconds: 120)
        let before = mac.tryTimes.count
        mac.input.online = true
        mac.run(seconds: 10)
        mac.input.online = false
        mac.run(seconds: 30)
        let after = Array(mac.tryTimes.dropFirst(before))
        XCTAssertEqual(after.count, 2, "After the lost time, and 10 seconds later")
        XCTAssertEqual(after[1] - after[0], 10)
    }

    func testASleepStartsTheLostTimeAgain() {
        var mac = HopMac()
        mac.wifi.air = []
        mac.loseWiFi()
        mac.run(seconds: 10)
        mac.sleep(3600)
        mac.sample()
        XCTAssertEqual(mac.state, .waiting)
        XCTAssertEqual(mac.wifi.scans, [], "A Mac that wakes with no network waits the lost time first")
        mac.run(seconds: 16)
        XCTAssertEqual(mac.wifi.scans.count, 1)
    }

    // MARK: What stops it

    func testARefusedPasswordIsTriedTwiceAndThenNotUntilTheUserSavesAgain() {
        var mac = HopMac()
        mac.password = "wrong"
        mac.loseWiFi()
        mac.run(seconds: 600)
        guard case .failed(.wrongPassword, _) = mac.state else { return XCTFail("\(mac.state.code)") }
        XCTAssertEqual(mac.wifi.joins.count, HotspotHop.passwordTries)
        XCTAssertEqual(mac.wifi.scans.count, HotspotHop.passwordTries, "No scan for a password that is refused")
        // The user saves the right one.
        mac.password = HopMac.password
        mac.input.saves += 1
        mac.run(seconds: 4)
        XCTAssertTrue(joined(mac.state))
        XCTAssertEqual(mac.wifi.joins.count, 3)
    }

    func testWithoutThePermissionNothingIsScanned() {
        var mac = HopMac()
        mac.input.permissionDenied = true
        mac.loseWiFi()
        mac.run(seconds: 30)
        guard case .failed(.noPermission, let at) = mac.state else { return XCTFail("\(mac.state.code)") }
        XCTAssertEqual(mac.wifi.scans, [])
        mac.run(seconds: 60)
        XCTAssertEqual(mac.state, .failed(.noPermission, at: at), "The time of the first refusal stays")
        // The user allows it.
        mac.input.permissionDenied = false
        mac.run(seconds: 2)
        XCTAssertTrue(joined(mac.state))
    }

    func testANameThatMacOSHidesIsAFailureOfThePermission() {
        var mac = HopMac()
        mac.wifi.scanFailure = .noPermission
        mac.loseWiFi()
        mac.run(seconds: 30)
        guard case .failed(.noPermission, _) = mac.state else { return XCTFail("\(mac.state.code)") }
        XCTAssertEqual(mac.wifi.joins, [])
    }

    func testWithWiFiOffNothingIsScannedAndThePowerIsNotChanged() {
        var mac = HopMac()
        mac.wifi.powered = false
        mac.loseWiFi()
        mac.run(seconds: 60)
        guard case .failed(.wifiOff, _) = mac.state else { return XCTFail("\(mac.state.code)") }
        XCTAssertEqual(mac.wifi.scans, [])
        XCTAssertEqual(mac.wifi.powered, false)
        mac.wifi.powered = nil
        mac.run(seconds: 60)
        guard case .failed(.noWiFi, _) = mac.state else { return XCTFail("\(mac.state.code)") }
    }

    func testAPasswordThatIsNotInTheKeychainIsAFailure() {
        var mac = HopMac()
        mac.password = nil
        mac.loseWiFi()
        mac.run(seconds: 30)
        guard case .failed(.noPassword, _) = mac.state else { return XCTFail("\(mac.state.code)") }
        XCTAssertEqual(mac.wifi.joins, [])
    }

    func testAnOpenNetworkWithTheNameOfTheHotspotIsNeverJoined() {
        func twin(rssi: Int) -> WiFiSeen {
            WiFiSeen(name: HopMac.hotspot, sighting: WiFiSighting(rssi: rssi, channel: 1), security: .open)
        }
        // An open network with the name of the phone and a stronger signal.
        var mac = HopMac()
        mac.wifi.others = [twin(rssi: -30)]
        mac.loseWiFi()
        mac.run(seconds: 20)
        XCTAssertTrue(joined(mac.state))
        XCTAssertEqual(mac.wifi.joined.map(\.security), [.personal], "The phone, not the open network")
        XCTAssertEqual(mac.wifi.joined.first?.sighting.rssi, -52)
        // The open network alone.
        mac = HopMac()
        mac.wifi.air = []
        mac.wifi.others = [twin(rssi: -30)]
        mac.loseWiFi()
        mac.run(seconds: 120)
        guard case .failed(.notSecure, _) = mac.state else { return XCTFail("\(mac.state.code)") }
        XCTAssertEqual(mac.wifi.joins, [], "No join")
        XCTAssertGreaterThan(mac.wifi.scans.count, 1, "The phone can come on the air later")
        mac.wifi.air = [HopMac.hotspot]
        mac.run(seconds: 62)
        XCTAssertEqual(mac.wifi.joined.map(\.security), [.personal])
    }

    func testOnlyANetworkWithAPasswordCountsAsTheHotspot() {
        func seen(_ name: String, _ rssi: Int, _ security: WiFiSecurity) -> WiFiSeen {
            WiFiSeen(name: name, sighting: WiFiSighting(rssi: rssi, channel: 6), security: security)
        }
        let name = "Mert's iPhone"
        let air = [seen("Cafe", -20, .personal), seen(HopMac.hotspot, -30, .open), seen(HopMac.hotspot, -70, .personal), seen(name, -60, .personal)]
        let pick = WiFiPick.hotspot(name, among: air)
        XCTAssertEqual(pick.index, 3, "The strongest that takes a password, with either apostrophe")
        XCTAssertEqual(pick.scan, .found(WiFiSighting(rssi: -60, channel: 6)))
        XCTAssertEqual(WiFiPick.hotspot(name, among: Array(air.prefix(2))).scan, .failed(.notSecure))
        XCTAssertNil(WiFiPick.hotspot(name, among: Array(air.prefix(2))).index)
        XCTAssertEqual(WiFiPick.hotspot(name, among: [air[0], seen(name, -30, .other)]).scan, .notFound, "WEP and a network with a user name")
        XCTAssertEqual(WiFiPick.hotspot(name, among: []).scan, .notFound)
    }

    func testOffNotSetUpNoAgentAndAStopDoNothing() {
        let changes: [(String, (inout HotspotHop.Input) -> Void)] = [
            ("the feature is off", { $0.on = false }),
            ("no hotspot is set up", { $0.name = "  " }),
            ("no agent holds the Mac awake", { $0.agentHolds = false }),
            ("a stop is in force", { $0.stopped = true }),
        ]
        for (name, change) in changes {
            var mac = HopMac()
            change(&mac.input)
            mac.loseWiFi()
            mac.run(seconds: 120)
            XCTAssertEqual(mac.state, .idle, name)
            XCTAssertEqual(mac.actions, [], name)
            XCTAssertEqual(mac.wifi.scans, [], name)
        }
    }

    func testTheTriesEndWhenTheAgentsCountNoMore() {
        var mac = HopMac()
        mac.wifi.air = []
        mac.loseWiFi()
        mac.run(seconds: 60)
        let tries = mac.tryTimes.count
        XCTAssertGreaterThan(tries, 0)
        // The offline rule let go of the agents.
        mac.input.agentHolds = false
        mac.run(seconds: 600)
        XCTAssertEqual(mac.tryTimes.count, tries)
        guard case .notFound = mac.state else { return XCTFail("The last result stays: \(mac.state.code)") }
    }

    func testAPathThatComesBackByItselfEndsTheTries() {
        var mac = HopMac()
        mac.loseWiFi()
        mac.run(seconds: 10)
        XCTAssertEqual(mac.state, .waiting)
        mac.wifi.air.insert(HopMac.cafe)
        mac.wifi.current = HopMac.cafe
        mac.input.online = true
        mac.run(seconds: 60)
        XCTAssertEqual(mac.state, .idle)
        XCTAssertEqual(mac.wifi.joins, [])
    }

    func testAPathThatComesBackDuringTheScanIsNotLeftForTheHotspot() {
        var mac = HopMac()
        mac.loseWiFi()
        mac.runsJobsAtOnce = false
        mac.run(seconds: 20)
        XCTAssertEqual(mac.state, .scanning)
        XCTAssertNotNil(mac.waiting)
        // No second action while one runs.
        mac.run(seconds: 30)
        XCTAssertEqual(mac.actions.count, 1)
        // The Wi-Fi is back before the job ran.
        mac.wifi.current = HopMac.cafe
        mac.input.online = true
        mac.sample()
        mac.finish()
        XCTAssertEqual(mac.wifi.joins, [], "A network that works is never left")
        XCTAssertEqual(mac.state, .idle)
    }

    func testJoinedWithNoPathIsTriedAgainAfterTheSettleTime() {
        var mac = HopMac()
        mac.loseWiFi()
        mac.run(seconds: 18)
        XCTAssertTrue(joined(mac.state))
        // The phone has the Mac on its hotspot and gives it no path.
        mac.input.online = false
        mac.run(seconds: 18)
        XCTAssertEqual(mac.wifi.joins.count, 1)
        mac.run(seconds: 4)
        XCTAssertEqual(mac.wifi.joins.count, 2)
    }

    // MARK: The way back

    func testTheMacGoesBackWhenTheOldWiFiIsSeenAgain() {
        var mac = HopMac()
        mac.run(seconds: 10)
        mac.loseWiFi()
        mac.run(seconds: 20)
        XCTAssertTrue(joined(mac.state))
        mac.run(seconds: 240)
        XCTAssertTrue(joined(mac.state), "The old network is not on the air")
        XCTAssertEqual(mac.wifi.joins.count, 1)
        mac.wifi.air.insert(HopMac.cafe)
        mac.run(seconds: 122)
        guard case .hoppedBack = mac.state else { return XCTFail("\(mac.state.code)") }
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot, HopMac.cafe])
        XCTAssertEqual(mac.wifi.joinPasswords, [HopMac.password, nil], "macOS has the password of a network it knows")
        XCTAssertEqual(mac.wifi.current, HopMac.cafe)
    }

    func testTheWayBackIsLookedForEveryTwoMinutesAndLessOftenInABag() {
        func scansForCafe(_ change: (inout HotspotHop.Input) -> Void) -> Int {
            var mac = HopMac()
            mac.run(seconds: 10)
            mac.loseWiFi()
            mac.run(seconds: 20)
            change(&mac.input)
            mac.run(seconds: 1200)
            return mac.wifi.scans.filter { $0 == HopMac.cafe }.count
        }
        XCTAssertEqual(scansForCafe { _ in }, 10)
        XCTAssertEqual(scansForCafe { $0.lidClosed = true }, 10, "On power the lid does not matter")
        XCTAssertEqual(scansForCafe { $0.lidClosed = true; $0.onBattery = true }, 2)
        XCTAssertEqual(scansForCafe { $0.hopBack = false }, 0)
    }

    func testANetworkTheUserLeftBeforeTheLossIsNeverJoined() {
        // The user went from the cafe Wi-Fi to another network by hand.
        var mac = HopMac()
        mac.wifi.air.insert("Library")
        mac.wifi.known.insert("Library")
        mac.run(seconds: 10)
        mac.wifi.current = "Library"
        mac.run(seconds: 10)
        mac.wifi.air.remove("Library")
        mac.wifi.current = nil
        mac.input.online = false
        mac.run(seconds: 20)
        XCTAssertTrue(joined(mac.state))
        // The cafe Wi-Fi is on the air the whole time.
        mac.run(seconds: 600)
        XCTAssertTrue(joined(mac.state))
        XCTAssertFalse(mac.wifi.scans.contains(HopMac.cafe))
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot])
    }

    func testAMacThatWasOnNoWiFiBeforeTheLossGoesNowhere() {
        // On a cable, after the user left the Wi-Fi by hand.
        var mac = HopMac()
        mac.run(seconds: 10)
        mac.wifi.current = nil
        mac.run(seconds: 10)
        mac.input.online = false
        mac.run(seconds: 20)
        XCTAssertTrue(joined(mac.state))
        mac.run(seconds: 600)
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot])
    }

    func testANetworkThatWasReadBeforeAnAgentWorkedIsOld() {
        var mac = HopMac()
        mac.run(seconds: 10)
        mac.input.agentHolds = false
        mac.run(seconds: 10)
        // The user changes the network while nothing is read.
        mac.wifi.current = "Library"
        mac.input.agentHolds = true
        mac.runsJobsAtOnce = false
        mac.sample()
        // The way is lost before the first look came back.
        mac.wifi.current = nil
        mac.input.online = false
        mac.sample()
        mac.finish()
        mac.runsJobsAtOnce = true
        mac.run(seconds: 20)
        XCTAssertTrue(joined(mac.state))
        mac.run(seconds: 600)
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot], "Not back to the cafe Wi-Fi the user left")
    }

    func testAWayBackThatMacOSRefusesIsTriedOnceAndTheMacStaysOnTheHotspot() {
        var mac = HopMac()
        mac.run(seconds: 10)
        mac.loseWiFi()
        mac.run(seconds: 20)
        mac.wifi.air.insert(HopMac.cafe)
        mac.wifi.known = []
        mac.run(seconds: 1200)
        XCTAssertTrue(joined(mac.state))
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot], "A network macOS does not know is not tried")
        mac = HopMac()
        mac.run(seconds: 10)
        mac.loseWiFi()
        mac.run(seconds: 20)
        mac.wifi.air.insert(HopMac.cafe)
        mac.wifi.joinFailure = .other
        mac.run(seconds: 1200)
        XCTAssertTrue(joined(mac.state))
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot, HopMac.cafe], "Once")
        XCTAssertEqual(mac.wifi.current, HopMac.hotspot)
    }

    func testAMacThatLeftTheHotspotIsNotOnItAnyMore() {
        var mac = HopMac()
        mac.run(seconds: 10)
        mac.loseWiFi()
        mac.run(seconds: 20)
        XCTAssertTrue(joined(mac.state))
        // The user selects another network in the Wi-Fi menu.
        mac.wifi.current = "Library"
        mac.run(seconds: 122)
        XCTAssertEqual(mac.state, .idle)
    }

    func testAHotspotThatMacOSJoinedByItselfCountsAsJoined() {
        var mac = HopMac()
        mac.wifi.air = []
        mac.run(seconds: 10)
        mac.loseWiFi()
        mac.run(seconds: 6)
        XCTAssertEqual(mac.state, .waiting)
        // "Ask to join hotspots: Automatic" woke the phone and joined it.
        mac.wifi.current = HopMac.hotspot
        mac.input.online = true
        mac.sample()
        XCTAssertTrue(joined(mac.state))
        XCTAssertEqual(mac.wifi.joins, [], "Agent Caffeine joined nothing")
        // The way back works from here too.
        mac.wifi.air = [HopMac.hotspot, HopMac.cafe]
        mac.run(seconds: 122)
        guard case .hoppedBack = mac.state else { return XCTFail("\(mac.state.code)") }
    }

    func testAHotspotTheUserJoinedByHandIsNoHop() {
        var mac = HopMac()
        mac.run(seconds: 10)
        mac.wifi.current = HopMac.hotspot
        mac.run(seconds: 600)
        XCTAssertEqual(mac.state, .idle)
        XCTAssertEqual(mac.wifi.scans, [])
    }

    // MARK: Names

    func testStraightAndCurlyApostrophesAreTheSameName() {
        XCTAssertTrue(HotspotName.matches("Mert's iPhone", "Mert\u{2019}s iPhone"))
        XCTAssertTrue(HotspotName.matches("Mert\u{2018}s iPhone", "Mert's iPhone"))
        XCTAssertFalse(HotspotName.matches("Mert's iPhone", "Merts iPhone"))
        XCTAssertFalse(HotspotName.matches("mert's iphone", "Mert's iPhone"), "A name of a network has capitals")
        XCTAssertEqual(HotspotName.spellings(of: "Mert's iPhone"), ["Mert's iPhone", "Mert\u{2019}s iPhone"])
        XCTAssertEqual(HotspotName.spellings(of: "Mert\u{2019}s iPhone"), ["Mert\u{2019}s iPhone", "Mert's iPhone"])
        XCTAssertEqual(HotspotName.spellings(of: "Pixel 9"), ["Pixel 9"])
        XCTAssertEqual(HotspotName.cleaned("  Pixel 9 \n"), "Pixel 9")
        XCTAssertNil(HotspotName.cleaned("   "))
        XCTAssertNil(HotspotName.cleaned(nil))
    }

    func testANameTypedWithTheStraightApostropheJoinsTheHotspotOfAnIPhone() {
        var mac = HopMac()
        mac.input.name = "Mert's iPhone"
        mac.run(seconds: 10)
        mac.loseWiFi()
        mac.run(seconds: 20)
        XCTAssertTrue(joined(mac.state))
        XCTAssertEqual(mac.wifi.current, "Mert\u{2019}s iPhone")
        // And the Mac knows that it is on the hotspot.
        mac.run(seconds: 122)
        XCTAssertTrue(joined(mac.state))
    }

    // MARK: Who counts

    func testOnlyAnAgentAtWorkCounts() {
        func reading() -> AgentReading {
            AgentReading(
                agentID: "claude", displayName: "Claude Code", level: .state, identity: ProcessIdentity(pid: 1, startTime: 1),
                verdict: AgentVerdict(state: .working, confidence: .reported, reason: .reportsBusy)
            )
        }
        func decision(hold: Bool = true, _ cause: HoldCause?) -> HoldDecision {
            HoldDecision(hold: hold, lidClosedFlag: false, headline: .noAgents, perAgent: [AgentHold(reading: reading(), cause: cause)])
        }
        XCTAssertTrue(HotspotHop.agentHolds(decision(.working)))
        XCTAssertTrue(HotspotHop.agentHolds(decision(.waitingForUser)))
        XCTAssertTrue(HotspotHop.agentHolds(decision(.finishedRecently)))
        XCTAssertFalse(HotspotHop.agentHolds(decision(.open)), "An agent that is only open needs no network")
        XCTAssertFalse(HotspotHop.agentHolds(decision(nil)), "Let go, as by the offline rule")
        XCTAssertFalse(HotspotHop.agentHolds(decision(hold: false, .working)), "A stop")
        let manual = HoldDecision(
            hold: true, lidClosedFlag: false, headline: .manualHold(.one("build")), perAgent: [],
            manualHolds: [ManualHold.timed(id: "0a1b2c3d", length: 600, reason: "build", now: HopMac.start)]
        )
        XCTAssertFalse(HotspotHop.agentHolds(manual), "A hold from the command line alone joins nothing")
    }

    // MARK: Privacy

    func testNoStateHasAName() {
        var mac = HopMac()
        mac.run(seconds: 10)
        mac.loseWiFi()
        mac.run(seconds: 20)
        let states: [HotspotHop.State] = [
            .idle, .waiting, .scanning, mac.state, .notFound(at: mac.now), .hoppedBack(at: mac.now),
        ] + HopFailure.allCases.map { .failed($0, at: mac.now) }
        for state in states {
            let text = "\(state) \(state.code)"
            for secret in [HopMac.hotspot, "iPhone", HopMac.cafe, HopMac.password] {
                XCTAssertFalse(text.contains(secret), text)
            }
        }
        XCTAssertEqual(Set(states.map(\.code)).count, states.count)
    }

    /// The files of the feature that are compiled into the tests write
    /// no log and print nothing: a name cannot get out that way.
    func testTheCoreWritesNoLog() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Caffeinagent/Detection/Network")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThanOrEqual(files.count, 4)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for word in ["import os", "Logger(", "os_log", "NSLog(", "print(", "debugPrint("] {
                XCTAssertFalse(source.contains(word), "\(file.lastPathComponent) has \(word)")
            }
        }
    }
}
