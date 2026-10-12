import XCTest

/// The answer of macOS about Location Services, as the test sets it.
final class FakeLocation: LocationAsking {
    var permission = LocationPermission.notAsked
    /// What the user answers when asked.
    var answer = LocationPermission.allowed
    private(set) var asked = 0

    func ask(_ answered: @escaping (LocationPermission) -> Void) {
        asked += 1
        if permission == .notAsked { permission = answer }
        answered(permission)
    }
}

/// The settings of "Join your iPhone hotspot" and the loop that runs the
/// rules, with a fake air, a Keychain in memory and settings in memory.
@MainActor
final class HotspotHopLoopTests: XCTestCase {
    private static let start = HopMac.start

    private struct Parts {
        let wifi = FakeWiFi()
        let passwords = FakePasswordStore()
        let location = FakeLocation()
        let defaults = TestDefaults()
        var online = true
        var seconds: TimeInterval = 0
    }

    private var parts = Parts()

    override func setUp() async throws {
        parts = Parts()
        parts.wifi.air = [HopMac.cafe, HopMac.hotspot]
        parts.wifi.known = [HopMac.cafe]
        parts.wifi.passwords = [HopMac.hotspot: HopMac.password]
        parts.wifi.current = HopMac.cafe
    }

    private func loop() -> HotspotHopLoop {
        HotspotHopLoop(
            wifi: parts.wifi, passwords: parts.passwords, location: parts.location, defaults: parts.defaults,
            isOnline: { [unowned self] in self.parts.online },
            now: { [unowned self] in self.time },
            perform: { work, done in done(work()) }
        )
    }

    private var time: SampleTime {
        SampleTime(at: Self.start.addingTimeInterval(parts.seconds), awake: 100 + parts.seconds)
    }

    private func working() -> HoldDecision {
        let reading = AgentReading(
            agentID: "claude", displayName: "Claude Code", level: .state, identity: ProcessIdentity(pid: 1, startTime: 1),
            verdict: AgentVerdict(state: .working, confidence: .reported, reason: .reportsBusy)
        )
        return HoldDecision(hold: true, lidClosedFlag: false, headline: .working(.one("Claude Code")), perAgent: [AgentHold(reading: reading, cause: .working)])
    }

    /// Samples every 2 seconds. A join that works brings the path back.
    private func run(_ loop: HotspotHopLoop, seconds: TimeInterval, decision: HoldDecision? = nil) {
        for _ in 0..<Int(seconds / 2) {
            parts.seconds += 2
            if parts.wifi.current != nil { parts.online = true }
            loop.sampled(decision: decision ?? working(), context: FrameContext(offline: !parts.online), at: time)
        }
    }

    private func loseWiFi() {
        parts.wifi.air.remove(HopMac.cafe)
        parts.wifi.current = nil
        parts.online = false
    }

    // MARK: Settings

    func testTheFeatureIsOffUntilTheUserSwitchesItOn() {
        let settings = HotspotSettingsStore.load(from: parts.defaults)
        XCTAssertEqual(settings, HotspotSettings())
        XCTAssertFalse(settings.on)
        XCTAssertNil(settings.name)
        XCTAssertFalse(settings.isSetUp)
        XCTAssertTrue(settings.hopBack)
    }

    func testTheSettingsAreKeptAndAValueThatCannotBeReadKeepsItsDefault() throws {
        var settings = HotspotSettings()
        settings.on = true
        settings.name = HopMac.hotspot
        settings.passwordSaved = true
        settings.hopBack = false
        settings.saves = 3
        HotspotSettingsStore.save(settings, to: parts.defaults)
        XCTAssertEqual(HotspotSettingsStore.load(from: parts.defaults), settings)
        parts.defaults.set(Data(#"{"on":"yes","name":"  ","hopBack":false,"saves":"many"}"#.utf8), forKey: HotspotSettingsStore.key)
        let read = HotspotSettingsStore.load(from: parts.defaults)
        XCTAssertFalse(read.on)
        XCTAssertNil(read.name, "An empty name is none")
        XCTAssertFalse(read.hopBack)
        XCTAssertEqual(read.saves, 0)
        parts.defaults.set(Data("not json".utf8), forKey: HotspotSettingsStore.key)
        XCTAssertEqual(HotspotSettingsStore.load(from: parts.defaults), HotspotSettings())
    }

    func testThePasswordIsNeverInTheSettings() throws {
        let loop = loop()
        loop.setOn(true)
        loop.save(name: HopMac.hotspot, password: HopMac.password)
        XCTAssertEqual(parts.passwords.password, HopMac.password)
        for (key, value) in parts.defaults.dictionaryRepresentation() {
            let text = (value as? Data).map { String(decoding: $0, as: UTF8.self) } ?? "\(value)"
            XCTAssertFalse(text.contains(HopMac.password), key)
        }
        XCTAssertEqual(Array(parts.defaults.dictionaryRepresentation().keys), [HotspotSettingsStore.key])
    }

    func testWhileTheFeatureIsOffNothingIsReadOrAsked() {
        let loop = loop()
        loseWiFi()
        run(loop, seconds: 120)
        XCTAssertEqual(loop.view.state, .idle)
        XCTAssertEqual(parts.wifi.scans, [])
        XCTAssertEqual(parts.passwords.loads, 0)
        XCTAssertEqual(parts.location.asked, 0)
        // Save does nothing while the switch is off.
        loop.save(name: HopMac.hotspot, password: HopMac.password)
        XCTAssertNil(parts.passwords.password)
        XCTAssertEqual(parts.location.asked, 0)
    }

    func testThePermissionIsAskedBySaveAndNotByTheSwitch() {
        let loop = loop()
        loop.setOn(true)
        XCTAssertEqual(parts.location.asked, 0, "Not by the switch")
        loop.save(name: "", password: HopMac.password)
        XCTAssertEqual(loop.view.saveNote, .incomplete)
        loop.save(name: HopMac.hotspot, password: "")
        XCTAssertEqual(loop.view.saveNote, .incomplete, "No password is saved yet")
        XCTAssertEqual(parts.location.asked, 0)
        XCTAssertFalse(loop.view.settings.isSetUp)
        loop.save(name: "  \(HopMac.hotspot) ", password: HopMac.password)
        XCTAssertEqual(parts.location.asked, 1)
        XCTAssertEqual(loop.view.saveNote, .saved(.allowed))
        XCTAssertEqual(loop.view.permission, .allowed)
        XCTAssertEqual(loop.view.settings.name, HopMac.hotspot)
        XCTAssertTrue(loop.view.settings.isSetUp)
        XCTAssertEqual(HotspotSettingsStore.load(from: parts.defaults), loop.view.settings)
        // A new name with the password field left empty keeps the password.
        loop.save(name: "Pixel 9", password: "")
        XCTAssertEqual(loop.view.settings.name, "Pixel 9")
        XCTAssertEqual(parts.passwords.password, HopMac.password)
        XCTAssertEqual(loop.view.settings.saves, 2)
    }

    func testARefusedPermissionAndAKeychainThatRefusesAreSaid() {
        parts.location.answer = .denied
        var loop = loop()
        loop.setOn(true)
        loop.save(name: HopMac.hotspot, password: HopMac.password)
        XCTAssertEqual(loop.view.saveNote, .saved(.denied))
        XCTAssertEqual(loop.view.permission, .denied)
        parts = Parts()
        parts.passwords.refusesSave = true
        loop = self.loop()
        loop.setOn(true)
        loop.save(name: HopMac.hotspot, password: HopMac.password)
        XCTAssertEqual(loop.view.saveNote, .keychainFailed)
        XCTAssertFalse(loop.view.settings.isSetUp)
        XCTAssertEqual(parts.location.asked, 0)
    }

    func testSwitchingOffForgetsTheNameAndThePassword() {
        let loop = loop()
        loop.setOn(true)
        loop.save(name: HopMac.hotspot, password: HopMac.password)
        loop.setOn(false)
        XCTAssertNil(parts.passwords.password)
        XCTAssertNil(loop.view.settings.name)
        XCTAssertFalse(loop.view.settings.on)
        XCTAssertNil(loop.view.saveNote)
        let stored = try? XCTUnwrap(parts.defaults.data(forKey: HotspotSettingsStore.key))
        XCTAssertFalse(String(decoding: stored ?? Data(), as: UTF8.self).contains("iPhone"))
        loseWiFi()
        run(loop, seconds: 120)
        XCTAssertEqual(parts.wifi.scans, [])
    }

    // MARK: The loop

    func testTheLoopJoinsTheHotspotWithThePasswordOfTheKeychain() {
        let loop = loop()
        var changes = 0
        loop.onChange = { changes += 1 }
        loop.setOn(true)
        loop.save(name: "Mert's iPhone", password: HopMac.password)
        run(loop, seconds: 10)
        XCTAssertEqual(parts.passwords.loads, 0, "The Keychain is read for a join only")
        loseWiFi()
        run(loop, seconds: 14)
        XCTAssertEqual(loop.view.state, .waiting)
        XCTAssertNil(loop.view.onHotspotSince)
        run(loop, seconds: 6)
        guard case .joined(let at) = loop.view.state else { return XCTFail(loop.view.state.code) }
        XCTAssertEqual(parts.wifi.joinPasswords, [HopMac.password])
        XCTAssertEqual(parts.wifi.current, HopMac.hotspot)
        XCTAssertEqual(loop.view.onHotspotSince, at)
        XCTAssertGreaterThan(changes, 3)
        // The cafe is on the air again: the Mac goes back.
        parts.wifi.air.insert(HopMac.cafe)
        run(loop, seconds: 244)
        guard case .hoppedBack = loop.view.state else { return XCTFail(loop.view.state.code) }
        XCTAssertNil(loop.view.onHotspotSince)
        XCTAssertEqual(parts.wifi.current, HopMac.cafe)
    }

    func testTheWayBackCanBeSwitchedOff() {
        let loop = loop()
        loop.setOn(true)
        loop.save(name: HopMac.hotspot, password: HopMac.password)
        loop.setHopBack(false)
        run(loop, seconds: 10)
        loseWiFi()
        run(loop, seconds: 20)
        parts.wifi.air.insert(HopMac.cafe)
        run(loop, seconds: 600)
        XCTAssertEqual(parts.wifi.joins, [HopMac.hotspot])
        XCTAssertNotNil(loop.view.onHotspotSince)
    }

    func testTheUserWhoPicksTheHotspotIsNotMovedBackToTheWiFiTheyLeft() {
        let loop = loop()
        loop.setOn(true)
        loop.save(name: HopMac.hotspot, password: HopMac.password)
        run(loop, seconds: 10)
        // An agent works on the cafe Wi-Fi, and the user clicks the
        // hotspot in the Wi-Fi menu. The switch takes 4 seconds.
        parts.wifi.current = nil
        parts.online = false
        run(loop, seconds: 4)
        parts.wifi.current = HopMac.hotspot
        run(loop, seconds: 300)
        XCTAssertEqual(parts.wifi.joins, [], "Agent Caffeine joined nothing")
        XCTAssertEqual(parts.wifi.current, HopMac.hotspot)
        XCTAssertNotNil(loop.view.onHotspotSince)
        XCTAssertEqual(loop.view.state.code, "joined")
    }

    func testAHoldFromTheCommandLineAloneJoinsNothing() {
        let loop = loop()
        loop.setOn(true)
        loop.save(name: HopMac.hotspot, password: HopMac.password)
        let manual = HoldDecision(
            hold: true, lidClosedFlag: false, headline: .manualHold(.one("build")), perAgent: [],
            manualHolds: [ManualHold.timed(id: "0a1b2c3d", length: 600, reason: "build", now: Self.start)]
        )
        loseWiFi()
        run(loop, seconds: 120, decision: manual)
        XCTAssertEqual(loop.view.state, .idle)
        XCTAssertEqual(parts.wifi.scans, [])
    }

    func testARefusedPermissionShowsAsTheFailure() {
        parts.location.answer = .denied
        let loop = loop()
        loop.setOn(true)
        loop.save(name: HopMac.hotspot, password: HopMac.password)
        loseWiFi()
        run(loop, seconds: 30)
        guard case .failed(.noPermission, _) = loop.view.state else { return XCTFail(loop.view.state.code) }
        XCTAssertEqual(parts.wifi.scans, [])
        // The user allows it in System Settings.
        parts.location.permission = .allowed
        loop.refresh()
        XCTAssertEqual(loop.view.permission, .allowed)
        run(loop, seconds: 4)
        XCTAssertNotNil(loop.view.onHotspotSince)
    }

    func testAStartWithTheFeatureOnReadsTheSettings() {
        var settings = HotspotSettings()
        settings.on = true
        settings.name = HopMac.hotspot
        settings.passwordSaved = true
        settings.saves = 1
        HotspotSettingsStore.save(settings, to: parts.defaults)
        parts.passwords.password = HopMac.password
        parts.location.permission = .allowed
        let loop = loop()
        XCTAssertEqual(loop.view.settings, settings)
        XCTAssertEqual(loop.view.permission, .allowed)
        XCTAssertEqual(parts.location.asked, 0, "Nothing is asked at launch")
        loseWiFi()
        run(loop, seconds: 20)
        XCTAssertNotNil(loop.view.onHotspotSince)
    }

    // MARK: The setting of macOS

    func testAskToJoinHotspotsIsReadFromTheSettingsOfTheWiFi() {
        XCTAssertEqual(HotspotAutoJoin.read(from: ["AutoHotspotMode": "Automatic"]), .automatic)
        XCTAssertEqual(HotspotAutoJoin.read(from: ["AutoHotspotMode": "Ask to Join"]), .notAutomatic)
        XCTAssertEqual(HotspotAutoJoin.read(from: ["AutoHotspotMode": "Never"]), .notAutomatic)
        XCTAssertNil(HotspotAutoJoin.read(from: ["Version": 7]), "A macOS without the choice")
        XCTAssertNil(HotspotAutoJoin.read(from: ["AutoHotspotMode": 2]))
        XCTAssertNil(HotspotAutoJoin.read(from: nil))
    }
}
