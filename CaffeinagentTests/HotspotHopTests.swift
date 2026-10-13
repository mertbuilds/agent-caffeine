import CoreWLAN
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

    func testARefusedPasswordGetsItsTriesBackWhenTheMacWasOnlineAgain() {
        var mac = HopMac()
        mac.run(seconds: 10)
        // One refusal, then the Wi-Fi is back for an hour.
        mac.loseWiFi()
        mac.wifi.joinFailure = .wrongPassword
        mac.run(seconds: 20)
        XCTAssertEqual(mac.wifi.joins.count, 1)
        mac.wifi.air.insert(HopMac.cafe)
        mac.wifi.current = HopMac.cafe
        mac.input.online = true
        mac.run(seconds: 3600)
        // One refusal in the next loss, and then the hotspot is fine.
        mac.loseWiFi()
        mac.run(seconds: 20)
        XCTAssertEqual(mac.wifi.joins.count, 2)
        guard case .failed(.wrongPassword, _) = mac.state else { return XCTFail("\(mac.state.code)") }
        mac.wifi.joinFailure = nil
        mac.run(seconds: 12)
        XCTAssertTrue(joined(mac.state), "Each loss has its own tries")
        XCTAssertEqual(mac.wifi.joins.count, 3)
    }

    func testAJoinThatTimesOutIsNoRefusedPassword() {
        var mac = HopMac()
        mac.loseWiFi()
        mac.wifi.joinFailure = .timeout
        mac.run(seconds: 400)
        guard case .failed(.timeout, _) = mac.state else { return XCTFail("\(mac.state.code)") }
        XCTAssertGreaterThan(mac.wifi.joins.count, HotspotHop.passwordTries + 2, "It is tried again on the schedule")
        mac.wifi.joinFailure = nil
        mac.run(seconds: 62)
        XCTAssertTrue(joined(mac.state))
    }

    func testOnlyAnErrorOfTheKeyCountsAsARefusedPassword() {
        XCTAssertEqual(HopFailure.of(coreWLAN: CWErr.cwInvalidPMKErr.rawValue, joining: true), .wrongPassword)
        XCTAssertEqual(HopFailure.of(coreWLAN: CWErr.cwChallengeFailureErr.rawValue, joining: true), .wrongPassword)
        XCTAssertEqual(HopFailure.of(coreWLAN: CWErr.cwInvalidPMKErr.rawValue, joining: false), .other, "A scan sends no password")
        // A weak signal gives this one: the hotspot said nothing of the password.
        XCTAssertEqual(HopFailure.of(coreWLAN: CWErr.cwSupplicantTimeoutErr.rawValue, joining: true), .timeout)
        XCTAssertEqual(HopFailure.of(coreWLAN: CWErr.cwTimeoutErr.rawValue, joining: true), .timeout)
        XCTAssertEqual(HopFailure.of(coreWLAN: CWErr.cwOperationNotPermittedErr.rawValue, joining: false), .noPermission)
        XCTAssertEqual(HopFailure.of(coreWLAN: CWErr.cwAssociationDeniedErr.rawValue, joining: true), .other)
        XCTAssertEqual(HopFailure.of(coreWLAN: CWErr.cwapFullErr.rawValue, joining: true), .other)
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

    func testALockedKeychainIsNotAskedAndIsTriedAgainLater() {
        var mac = HopMac()
        mac.passwordFailure = .keychainLocked
        mac.loseWiFi()
        mac.run(seconds: 120)
        guard case .failed(.keychainLocked, _) = mac.state else { return XCTFail("\(mac.state.code)") }
        XCTAssertEqual(mac.wifi.scans, [])
        XCTAssertEqual(mac.wifi.joins, [])
        XCTAssertGreaterThan(mac.tryTimes.count, 2, "On the schedule")
        // The user unlocks it.
        mac.passwordFailure = nil
        mac.run(seconds: 62)
        XCTAssertTrue(joined(mac.state))
    }

    func testACallThatMacOSNeverAnswersIsAFailedTry() {
        // Offline: the try fails, nothing is joined, and the next try comes.
        var mac = HopMac()
        mac.loseWiFi()
        mac.wifi.readFailure = .timeout
        mac.run(seconds: 120)
        guard case .failed(.timeout, _) = mac.state else { return XCTFail("\(mac.state.code)") }
        XCTAssertEqual(mac.wifi.joins, [], "Nothing says that the Mac is not on the hotspot")
        XCTAssertNil(mac.hop.pending)
        XCTAssertGreaterThan(mac.tryTimes.count, 2)
        mac.wifi.readFailure = nil
        mac.run(seconds: 62)
        XCTAssertTrue(joined(mac.state))
        // The Keychain gives no answer.
        mac = HopMac()
        mac.loseWiFi()
        mac.passwordFailure = .timeout
        mac.run(seconds: 30)
        guard case .failed(.timeout, _) = mac.state else { return XCTFail("\(mac.state.code)") }
        XCTAssertEqual(mac.wifi.scans, [])
        // On the hotspot: no answer is not "the Mac left the hotspot".
        mac = hopped(from: HopMac.cafe)
        mac.run(seconds: 122)
        mac.wifi.air.insert(HopMac.cafe)
        mac.wifi.readFailure = .timeout
        mac.run(seconds: 600)
        XCTAssertTrue(joined(mac.state))
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot])
        XCTAssertNil(mac.hop.pending)
        mac.wifi.readFailure = nil
        mac.run(seconds: 244)
        XCTAssertEqual(mac.wifi.current, HopMac.cafe, "The way back is still there")
        // Online with an agent: the name is asked for again.
        mac = HopMac()
        mac.wifi.readFailure = .timeout
        mac.run(seconds: 30)
        XCTAssertEqual(mac.state, .idle)
        XCTAssertGreaterThan(mac.actions.count, 3)
    }

    func testACallWithNoTimeLimitGetsOne() {
        let calls = TimedCalls(label: "com.caffeinagent.tests.timed")
        XCTAssertEqual(calls.run(5) { 7 }, 7)
        let hang = DispatchSemaphore(value: 0)
        let ended = expectation(description: "the call that hung ended")
        let began = Date()
        let late: Int? = calls.run(0.05) {
            hang.wait()
            ended.fulfill()
            return 1
        }
        XCTAssertNil(late, "The caller goes on")
        XCTAssertLessThan(Date().timeIntervalSince(began), 2)
        XCTAssertNil(calls.run(5) { 2 }, "No second call while the first one hangs")
        hang.signal()
        wait(for: [ended], timeout: 5)
        var after: Int?
        for _ in 0..<100 where after == nil {
            after = calls.run(5) { 3 }
            if after == nil { Thread.sleep(forTimeInterval: 0.01) }
        }
        XCTAssertEqual(after, 3, "And it works again when that one ended")
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

    func testTheTriesOfOneLossEndAfterHalfAnHour() {
        // An agent with a busy command, or the offline rule on Never:
        // the agents count for as long as the Mac is offline.
        var mac = HopMac()
        mac.wifi.air = []
        mac.loseWiFi()
        mac.run(seconds: 4 * 3600)
        let first = try? XCTUnwrap(mac.tryTimes.first)
        let last = try? XCTUnwrap(mac.tryTimes.last)
        XCTAssertLessThanOrEqual((last ?? 0) - (first ?? 0), HotspotHop.tryLimit)
        XCTAssertGreaterThan((last ?? 0) - (first ?? 0), HotspotHop.tryLimit - 62)
        XCTAssertEqual(HotspotHop.tryLimit, 1800)
        guard case .notFound(let at) = mac.state else { return XCTFail("\(mac.state.code)") }
        XCTAssertLessThan(at.timeIntervalSince(HopMac.start), 1900, "The line says when the last try was")
        // A sleep gives no new tries: the loss is the same.
        let tries = mac.tryTimes.count
        mac.sleep(3600)
        mac.run(seconds: 10)
        guard case .notFound = mac.state else { return XCTFail("No try comes, so nothing waits: \(mac.state.code)") }
        mac.run(seconds: 590)
        XCTAssertEqual(mac.tryTimes.count, tries)
        guard case .notFound = mac.state else { return XCTFail("The last result stays: \(mac.state.code)") }
        // The next loss has its own half hour.
        mac.input.online = true
        mac.run(seconds: 10)
        mac.input.online = false
        mac.run(seconds: 20)
        XCTAssertEqual(mac.tryTimes.count, tries + 1)
    }

    func testARefusedPasswordIsStillSaidAfterASleep() {
        var mac = HopMac()
        mac.password = "wrong"
        mac.loseWiFi()
        mac.run(seconds: 120)
        XCTAssertEqual(mac.wifi.joins.count, HotspotHop.passwordTries)
        // No try comes after the sleep, so the state does not say that
        // the Mac looks for the hotspot in a moment.
        mac.sleep(3600)
        mac.run(seconds: 10)
        guard case .failed(.wrongPassword, _) = mac.state else { return XCTFail("\(mac.state.code)") }
        mac.run(seconds: 120)
        guard case .failed(.wrongPassword, _) = mac.state else { return XCTFail("\(mac.state.code)") }
        XCTAssertEqual(mac.wifi.joins.count, HotspotHop.passwordTries)
        // One refusal leaves a try, and the state waits for it.
        mac = HopMac()
        mac.password = "wrong"
        mac.loseWiFi()
        mac.run(seconds: 20)
        XCTAssertEqual(mac.wifi.joins.count, 1)
        mac.sleep(3600)
        mac.run(seconds: 10)
        XCTAssertEqual(mac.state, .waiting)
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

    func testOnTheHotspotWithNoPathNothingIsJoinedASecondTime() {
        var mac = HopMac()
        mac.loseWiFi()
        mac.run(seconds: 18)
        XCTAssertTrue(joined(mac.state))
        // The phone has the Mac on its hotspot and gives it no path.
        mac.input.online = false
        mac.run(seconds: 600)
        XCTAssertEqual(mac.wifi.joins.count, 1, "The Mac is on the hotspot")
        XCTAssertEqual(mac.wifi.scans.count, 1)
        XCTAssertTrue(joined(mac.state))
        // A sleep changes nothing of that.
        mac.sleep(3600)
        mac.run(seconds: 60)
        XCTAssertTrue(joined(mac.state))
        XCTAssertEqual(mac.wifi.joins.count, 1)
        // The path comes: the Mac is on the hotspot as after any join.
        mac.input.online = true
        mac.run(seconds: 10)
        XCTAssertTrue(joined(mac.state))
        // A save on the hotspot does not make the next loss there a hop.
        mac.input.saves += 1
        mac.run(seconds: 10)
        mac.wifi.current = nil
        mac.input.online = false
        mac.run(seconds: 120)
        XCTAssertEqual(mac.wifi.joins.count, 1)
    }

    func testAJoinThatDoesNotHoldIsTriedAgainOnTheSchedule() {
        var mac = HopMac()
        mac.loseWiFi()
        for _ in 0..<200 {
            // Each join works, and the Mac is off the hotspot at once.
            if mac.input.online {
                mac.input.online = false
                mac.wifi.current = nil
            }
            mac.sample()
        }
        let waits = zip(mac.tryTimes, mac.tryTimes.dropFirst()).map { $1 - $0 }
        XCTAssertEqual(Array(waits.prefix(5)), [20, 20, 40, 60, 60], "The settle time first, then the schedule")
        XCTAssertEqual(mac.wifi.joins.count, mac.tryTimes.count)
    }

    func testAMacThatIsOnTheHotspotWithNoPathIsNotJoinedToIt() {
        // The user joined the hotspot by hand a moment ago, and the phone
        // gives no path. No look read the name yet.
        var mac = HopMac()
        mac.wifi.current = HopMac.hotspot
        mac.input.online = false
        mac.run(seconds: 600)
        XCTAssertEqual(mac.wifi.joins, [], "Never a join while the Mac is on the hotspot")
        XCTAssertEqual(mac.wifi.scans, [])
        XCTAssertEqual(mac.actions.count, 1, "One try read the name, and that was all")
        XCTAssertTrue(joined(mac.state))
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
        XCTAssertEqual(mac.wifi.joins.count, 1, "The first look that sees it joins nothing yet")
        mac.run(seconds: 120)
        guard case .hoppedBack = mac.state else { return XCTFail("\(mac.state.code)") }
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot, HopMac.cafe])
        XCTAssertEqual(mac.wifi.joinPasswords, [HopMac.password, nil], "macOS has the password of a network it knows")
        XCTAssertEqual(mac.wifi.current, HopMac.cafe)
    }

    func testAWiFiTheUserDisconnectedFromIsNotJoinedAgain() {
        // The user clicks Disconnect while an agent works. The cafe
        // Wi-Fi stays on the air, with a good signal.
        var mac = HopMac()
        mac.run(seconds: 10)
        mac.wifi.current = nil
        mac.input.online = false
        mac.run(seconds: 20)
        XCTAssertTrue(joined(mac.state))
        mac.run(seconds: 3600)
        XCTAssertTrue(joined(mac.state))
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot], "Going back would undo what the user did")
        XCTAssertEqual(mac.wifi.current, HopMac.hotspot)
        XCTAssertEqual(mac.wifi.scans.filter { $0 == HopMac.cafe }.count, 1, "The first look ends the way back, and its scans")
        // Not later either, when the network goes and comes.
        mac.wifi.air.remove(HopMac.cafe)
        mac.run(seconds: 600)
        mac.wifi.air.insert(HopMac.cafe)
        mac.run(seconds: 600)
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot])
        // A scan that failed is no look: the first one that runs counts.
        mac = HopMac()
        mac.run(seconds: 10)
        mac.wifi.current = nil
        mac.input.online = false
        mac.run(seconds: 20)
        mac.wifi.scanFailure = .timeout
        mac.run(seconds: 600)
        mac.wifi.scanFailure = nil
        mac.run(seconds: 3600)
        XCTAssertTrue(joined(mac.state))
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot])
    }

    func testAWiFiThatWasGoneAndCameBackIsJoinedAgain() {
        // The Mac went out of reach of the cafe Wi-Fi: the first look
        // on the hotspot does not see it.
        var mac = HopMac()
        mac.run(seconds: 10)
        mac.loseWiFi()
        mac.run(seconds: 20)
        XCTAssertTrue(joined(mac.state))
        mac.run(seconds: 122)
        XCTAssertEqual(mac.wifi.scans.filter { $0 == HopMac.cafe }.count, 1)
        mac.wifi.air.insert(HopMac.cafe)
        mac.run(seconds: 120)
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot], "Seen once")
        mac.run(seconds: 120)
        guard case .hoppedBack = mac.state else { return XCTFail("\(mac.state.code)") }
        XCTAssertEqual(mac.wifi.current, HopMac.cafe)
        // A first look that sees it with a weak signal: the Mac was at
        // the edge, and the network was as good as gone.
        mac = HopMac()
        mac.run(seconds: 10)
        mac.loseWiFi()
        mac.wifi.others = [WiFiSeen(name: HopMac.cafe, sighting: WiFiSighting(rssi: HotspotHop.backSignal - 1, channel: 6), security: .personal)]
        mac.run(seconds: 20)
        mac.run(seconds: 122)
        mac.wifi.others = []
        mac.wifi.air.insert(HopMac.cafe)
        mac.run(seconds: 240)
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
        // The first look does not see it.
        mac.run(seconds: 122)
        mac.wifi.air.insert(HopMac.cafe)
        mac.wifi.joinFailure = .other
        mac.run(seconds: 1200)
        XCTAssertTrue(joined(mac.state))
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot, HopMac.cafe], "Once")
        XCTAssertEqual(mac.wifi.current, HopMac.hotspot)
    }

    /// The Mac lost this Wi-Fi and is on the hotspot.
    private func hopped(from name: String, knownAs security: WiFiSecurity = .personal) -> HopMac {
        var mac = HopMac()
        mac.wifi.air = [name, HopMac.hotspot]
        mac.wifi.known = []
        mac.wifi.knownAs = [name: security]
        mac.wifi.current = name
        mac.run(seconds: 10)
        mac.wifi.air.remove(name)
        mac.wifi.current = nil
        mac.input.online = false
        mac.run(seconds: 20)
        XCTAssertTrue(joined(mac.state))
        return mac
    }

    func testTheWayBackGoesOnlyToTheSameNameToTheLetter() {
        // The lost network has a straight apostrophe. Another one with
        // the curly apostrophe is on the air, with a strong signal.
        var mac = hopped(from: "Bob's Cafe")
        mac.wifi.air.insert("Bob\u{2019}s Cafe")
        mac.run(seconds: 1200)
        XCTAssertTrue(joined(mac.state))
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot], "Another spelling is another network")
        XCTAssertEqual(Set(mac.wifi.scans.dropFirst()), ["Bob's Cafe"], "One scan for the name as macOS gave it")
        mac.wifi.air.insert("Bob's Cafe")
        mac.run(seconds: 300)
        XCTAssertEqual(mac.wifi.current, "Bob's Cafe")
    }

    func testTheWayBackNeverGoesToAnOpenNetwork() {
        let open = WiFiSeen(name: HopMac.cafe, sighting: WiFiSighting(rssi: -30, channel: 1), security: .open)
        // The lost network had a password. An open one with its name is
        // on the air.
        var mac = hopped(from: HopMac.cafe)
        mac.wifi.others = [open]
        mac.run(seconds: 1200)
        XCTAssertTrue(joined(mac.state))
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot])
        // With the real one on the air too, the real one is joined.
        mac.wifi.air.insert(HopMac.cafe)
        mac.run(seconds: 300)
        XCTAssertEqual(mac.wifi.joined.map(\.security), [.personal, .personal])
        XCTAssertEqual(mac.wifi.current, HopMac.cafe)
        // A lost network that is open, or asks for a user name, gets no
        // way back at all.
        for security in [WiFiSecurity.open, .other] {
            mac = hopped(from: HopMac.cafe, knownAs: security)
            mac.wifi.others = [WiFiSeen(name: HopMac.cafe, sighting: WiFiSighting(rssi: -30, channel: 1), security: security)]
            mac.run(seconds: 1200)
            XCTAssertTrue(joined(mac.state), "\(security)")
            XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot], "\(security)")
            XCTAssertFalse(mac.wifi.scans.contains(HopMac.cafe), "No scan for it either: \(security)")
        }
    }

    func testTheWayBackWaitsForAGoodSignalOnTwoLooksInARow() {
        func cafe(_ rssi: Int) -> [WiFiSeen] {
            [WiFiSeen(name: HopMac.cafe, sighting: WiFiSighting(rssi: rssi, channel: 11), security: .personal)]
        }
        /// Runs until the next look for the old network ended.
        func look(_ mac: inout HopMac, _ rssi: Int) {
            mac.wifi.others = cafe(rssi)
            let before = mac.wifi.scans.count
            while mac.wifi.scans.count == before { mac.sample() }
        }
        // At the edge of the old network: it is seen, and it is weak.
        var mac = hopped(from: HopMac.cafe)
        mac.wifi.others = cafe(HotspotHop.backSignal - 1)
        mac.run(seconds: 1200)
        XCTAssertTrue(joined(mac.state))
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot], "A weak network is not joined")
        // Good, weak, good: not two in a row.
        look(&mac, -60)
        look(&mac, -80)
        look(&mac, HotspotHop.backSignal)
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot])
        XCTAssertTrue(joined(mac.state))
        look(&mac, HotspotHop.backSignal)
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot, HopMac.cafe])
        guard case .hoppedBack = mac.state else { return XCTFail("\(mac.state.code)") }
        XCTAssertEqual(HotspotHop.backSignal, -70)
    }

    func testAStopEndsTheStateOnTheHotspotAndItsWayBack() {
        var mac = hopped(from: HopMac.cafe)
        // A pause, the switch or a safety stop.
        mac.input.stopped = true
        mac.sample()
        XCTAssertEqual(mac.state, .idle, "Nothing says On your iPhone hotspot during a stop")
        mac.wifi.air.insert(HopMac.cafe)
        mac.run(seconds: 600)
        mac.input.stopped = false
        mac.run(seconds: 600)
        XCTAssertEqual(mac.state, .idle)
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot], "The way back ended with the stop")
        XCTAssertFalse(mac.wifi.scans.contains(HopMac.cafe))
    }

    func testTheStateEndsSoonAfterTheUserPicksAnotherNetwork() {
        var mac = hopped(from: HopMac.cafe)
        mac.run(seconds: 30)
        // In the Wi-Fi menu, with no break that a sample sees.
        mac.wifi.current = "Library"
        mac.run(seconds: HotspotHop.lookInterval + HopMac.step)
        XCTAssertEqual(mac.state, .idle)
        XCTAssertFalse(mac.wifi.scans.contains(HopMac.cafe), "Reading the name needs no scan")
        // And with no agent at work.
        mac = hopped(from: HopMac.cafe)
        mac.input.agentHolds = false
        mac.run(seconds: 30)
        XCTAssertTrue(joined(mac.state))
        mac.wifi.current = nil
        mac.run(seconds: HotspotHop.lookInterval + HopMac.step)
        XCTAssertEqual(mac.state, .idle)
    }

    // MARK: Leaving the hotspot

    func testTheMacStaysOnTheHotspotAfterTheAgentsFinished() {
        var mac = hopped(from: HopMac.cafe)
        mac.input.agentHolds = false
        mac.run(seconds: 3600)
        XCTAssertTrue(joined(mac.state))
        XCTAssertEqual(mac.wifi.current, HopMac.hotspot, "Nothing takes the Mac off the hotspot")
        // Its Wi-Fi comes back.
        mac.wifi.air.insert(HopMac.cafe)
        mac.run(seconds: 244)
        XCTAssertEqual(mac.wifi.current, HopMac.cafe)
    }

    func testAPathThatIsLostOnTheHotspotStartsNoSecondJoin() {
        var mac = hopped(from: HopMac.cafe)
        mac.run(seconds: 30)
        // The user clicks Disconnect in the Wi-Fi menu, or the phone is
        // out of reach: nothing says which. The phone stays on the air.
        mac.wifi.current = nil
        mac.input.online = false
        mac.run(seconds: 30)
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot], "No second join")
        mac.run(seconds: 1200)
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot])
        XCTAssertEqual(mac.wifi.scans.count, 1, "And no scan")
        // A loss from another network is a new hop.
        mac.wifi.air.insert(HopMac.cafe)
        mac.wifi.current = HopMac.cafe
        mac.input.online = true
        mac.run(seconds: 10)
        XCTAssertEqual(mac.state, .idle)
        mac.loseWiFi()
        mac.run(seconds: 20)
        XCTAssertEqual(mac.wifi.joins, [HopMac.hotspot, HopMac.hotspot])
        XCTAssertTrue(joined(mac.state))
    }

    func testANewSaveLetsTheMacJoinAgainAfterItLeftTheHotspot() {
        var mac = hopped(from: HopMac.cafe)
        mac.run(seconds: 30)
        mac.wifi.current = nil
        mac.input.online = false
        mac.run(seconds: 60)
        XCTAssertEqual(mac.wifi.joins.count, 1)
        mac.input.saves += 1
        mac.run(seconds: 4)
        XCTAssertEqual(mac.wifi.joins.count, 2)
    }

    func testALossOnAHotspotTheUserJoinedStartsNoJoin() {
        // By hand and with no break: the state says nothing, and a look
        // saw the name.
        var mac = HopMac()
        mac.run(seconds: 10)
        mac.wifi.current = HopMac.hotspot
        mac.run(seconds: 10)
        mac.wifi.current = nil
        mac.input.online = false
        mac.run(seconds: 600)
        XCTAssertEqual(mac.wifi.joins, [])
        XCTAssertEqual(mac.wifi.scans, [])
        XCTAssertEqual(mac.state, .idle, "Nothing says that the Mac looks for the hotspot")
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
        // Agent Caffeine did not take the Mac here, so it takes it nowhere.
        mac.wifi.air = [HopMac.hotspot, HopMac.cafe]
        mac.run(seconds: 1200)
        XCTAssertTrue(joined(mac.state))
        XCTAssertEqual(mac.wifi.scans, [])
        XCTAssertEqual(mac.wifi.current, HopMac.hotspot)
    }

    func testAHotspotTheUserJoinedByHandIsNoHop() {
        var mac = HopMac()
        mac.run(seconds: 10)
        // The user clicks the hotspot in the Wi-Fi menu. The Mac is on
        // no network for 4 seconds, and the cafe Wi-Fi stays on the air.
        mac.wifi.current = nil
        mac.input.online = false
        mac.run(seconds: 4)
        mac.wifi.current = HopMac.hotspot
        mac.input.online = true
        mac.run(seconds: 1200)
        XCTAssertEqual(mac.wifi.scans, [], "No look for the Wi-Fi the user left")
        XCTAssertEqual(mac.wifi.joins, [])
        XCTAssertEqual(mac.wifi.current, HopMac.hotspot)
        XCTAssertTrue(joined(mac.state), "The Mac is on the hotspot")
        // With no break at all, nothing is said.
        mac = HopMac()
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

    func testTheNetworkOfAScanIsKeptForOneJoinOnly() {
        let found = FoundNetwork<String>()
        XCTAssertNil(found.take())
        found.keep(HopMac.hotspot)
        XCTAssertEqual(found.take(), HopMac.hotspot)
        XCTAssertNil(found.take(), "Given once")
        found.keep(HopMac.hotspot)
        found.forget()
        XCTAssertNil(found.take())
        // The fake air keeps it the same way: a second join needs a scan.
        let wifi = FakeWiFi()
        wifi.air = [HopMac.hotspot]
        wifi.passwords = [HopMac.hotspot: HopMac.password]
        XCTAssertEqual(wifi.scan(for: HopMac.hotspot), .found(WiFiSighting(rssi: -52, channel: 6)))
        XCTAssertEqual(wifi.associate(to: HopMac.hotspot, password: HopMac.password), .joined)
        XCTAssertEqual(wifi.associate(to: HopMac.hotspot, password: HopMac.password), .failed(.other))
        XCTAssertEqual(wifi.scan(for: HopMac.hotspot), .found(WiFiSighting(rssi: -52, channel: 6)))
        wifi.air = []
        XCTAssertEqual(wifi.scan(for: HopMac.hotspot), .notFound)
        XCTAssertEqual(wifi.associate(to: HopMac.hotspot, password: HopMac.password), .failed(.other), "A scan that found nothing forgets the one before")
    }

    func testAScanThatNoJoinFollowsKeepsNoNetwork() {
        let saved: () -> Result<String, HopFailure> = { .success(HopMac.password) }
        // A path came back during the scan for the hotspot.
        var wifi = FakeWiFi()
        wifi.air = [HopMac.hotspot]
        wifi.passwords = [HopMac.hotspot: HopMac.password]
        var asked = 0
        let pathBack = HotspotJob.run(.join(name: HopMac.hotspot), wifi: wifi, password: saved) {
            asked += 1
            return asked == 1
        }
        XCTAssertEqual(pathBack, .pathBack)
        XCTAssertEqual(wifi.scans, [HopMac.hotspot])
        XCTAssertEqual(wifi.associate(to: HopMac.hotspot, password: HopMac.password), .failed(.other))
        XCTAssertEqual(wifi.joined, [])
        // The first look that sees the old network, and a look that
        // sees it with a weak signal.
        for rssi in [-52, HotspotHop.backSignal - 1] {
            wifi = FakeWiFi()
            wifi.others = [WiFiSeen(name: HopMac.cafe, sighting: WiFiSighting(rssi: rssi, channel: 6), security: .personal)]
            wifi.known = [HopMac.cafe]
            wifi.current = HopMac.hotspot
            let back = HotspotJob.run(.back(hotspot: HopMac.hotspot, to: HopMac.cafe, seen: false), wifi: wifi, password: saved, mayJoin: { true })
            XCTAssertEqual(back, rssi == -52 ? .sawOld : .onHotspot)
            XCTAssertEqual(wifi.scans, [HopMac.cafe])
            XCTAssertEqual(wifi.associate(to: HopMac.cafe, password: nil), .failed(.other), "\(rssi)")
            XCTAssertEqual(wifi.joined, [], "\(rssi)")
            XCTAssertEqual(wifi.current, HopMac.hotspot)
        }
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
