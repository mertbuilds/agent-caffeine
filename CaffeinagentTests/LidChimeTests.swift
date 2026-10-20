import XCTest

@MainActor
final class LidChimeTests: XCTestCase {
    /// Counts the sounds and makes none.
    private final class SilentPlayer: LidChimePlaying {
        var played: [LidChimeSound] = []
        var missing = false

        func play(_ sound: LidChimeSound) -> Bool {
            played.append(sound)
            return !missing
        }
    }

    /// An agent works on wall power, with the lid open.
    private var onPower: LidChimeInputs {
        LidChimeInputs(lidClosed: false, enabled: true, holding: true, onBattery: false, flagWanted: true, helperEnabled: true, flagConfirmed: true)
    }

    /// The same on battery, with the helper's flag confirmed.
    private var onBattery: LidChimeInputs {
        var inputs = onPower
        inputs.onBattery = true
        return inputs
    }

    private func closed(_ inputs: LidChimeInputs, _ change: (inout LidChimeInputs) -> Void = { _ in }) -> LidChimeInputs {
        var inputs = inputs
        inputs.lidClosed = true
        change(&inputs)
        return inputs
    }

    /// The lid is open at 0 and closes at 10.
    private func closing(_ inputs: LidChimeInputs, _ change: (inout LidChimeInputs) -> Void = { _ in }) -> LidChime.Outcome? {
        var chime = LidChime()
        XCTAssertNil(chime.observe(inputs, now: 0))
        return chime.observe(closed(inputs, change), now: 10)
    }

    // MARK: Whether the Mac stays awake

    func testTheVerdictOnWallPowerNeedsOnlyTheHold() {
        XCTAssertEqual(LidChime.verdict(onPower), .chime)
        var inputs = onPower
        inputs.flagWanted = false
        inputs.helperEnabled = false
        inputs.flagConfirmed = false
        XCTAssertEqual(LidChime.verdict(inputs), .chime, "The power assertions keep a closed lid awake on wall power")
        inputs.holding = false
        XCTAssertEqual(LidChime.verdict(inputs), .silent(.notHolding))
    }

    func testTheVerdictOnBatteryNeedsTheConfirmedFlag() {
        XCTAssertEqual(LidChime.verdict(onBattery), .chime)
        var inputs = onBattery
        inputs.flagConfirmed = false
        XCTAssertEqual(LidChime.verdict(inputs), .wait, "The helper's answer can still come")
        inputs.helperEnabled = false
        XCTAssertEqual(LidChime.verdict(inputs), .silent(.helperNotSetUp))
        inputs.flagWanted = false
        XCTAssertEqual(LidChime.verdict(inputs), .silent(.lidSettingOff))
        // A flag that an earlier run left on is no promise.
        inputs.flagConfirmed = true
        XCTAssertEqual(LidChime.verdict(inputs), .silent(.lidSettingOff))
    }

    func testTheSwitchAndTheHoldComeFirst() {
        var inputs = onBattery
        inputs.enabled = false
        XCTAssertEqual(LidChime.verdict(inputs), .silent(.switchedOff))
        inputs.enabled = true
        inputs.holding = false
        XCTAssertEqual(LidChime.verdict(inputs), .silent(.notHolding))
    }

    // MARK: The lid closes

    func testALidThatClosesChimesOnceOnWallPowerAndOnBattery() {
        XCTAssertEqual(closing(onPower), .played)
        XCTAssertEqual(closing(onBattery), .played)
    }

    /// No hold: nothing works, a pause, off, a safety stop. The decision
    /// has no hold and no flag in all of them.
    func testNoChimeWhenTheMacWillSleep() {
        XCTAssertEqual(closing(onBattery) { $0.holding = false; $0.flagWanted = false; $0.flagConfirmed = false }, .silent(.notHolding))
        XCTAssertEqual(closing(onPower) { $0.holding = false }, .silent(.notHolding))
        XCTAssertEqual(closing(onBattery) { $0.helperEnabled = false; $0.flagConfirmed = false }, .silent(.helperNotSetUp))
        XCTAssertEqual(closing(onBattery) { $0.flagWanted = false; $0.flagConfirmed = false }, .silent(.lidSettingOff))
        XCTAssertEqual(closing(onBattery) { $0.enabled = false }, .silent(.switchedOff))
    }

    func testEveryLidThatClosesIsToldOnce() {
        var chime = LidChime()
        XCTAssertNil(chime.observe(onPower, now: 0))
        XCTAssertEqual(chime.observe(closed(onPower), now: 10), .played)
        for second in 11...40 {
            XCTAssertNil(chime.observe(closed(onPower), now: TimeInterval(second)), "The lid stays closed")
        }
        XCTAssertNil(chime.observe(onPower, now: 41))
        XCTAssertEqual(chime.observe(closed(onPower) { $0.holding = false }, now: 50), .silent(.notHolding))
        XCTAssertNil(chime.observe(closed(onPower), now: 52), "A hold that starts under a closed lid is no lid that closes")
    }

    // MARK: The wait for the helper

    func testTheChimeWaitsForTheFlag() {
        var chime = LidChime()
        XCTAssertNil(chime.observe(onBattery, now: 0))
        let unconfirmed = closed(onBattery) { $0.flagConfirmed = false }
        XCTAssertNil(chime.observe(unconfirmed, now: 10))
        XCTAssertTrue(chime.isWaiting)
        XCTAssertNil(chime.observe(unconfirmed, now: 10.25))
        XCTAssertNil(chime.observe(unconfirmed, now: 11.25))
        XCTAssertEqual(chime.observe(closed(onBattery), now: 11.5), .played, "Confirmed at the end of the wait")
        XCTAssertFalse(chime.isWaiting)
        XCTAssertNil(chime.observe(closed(onBattery), now: 11.75))
    }

    func testNoChimeWhenTheFlagDoesNotComeInTime() {
        var chime = LidChime()
        XCTAssertNil(chime.observe(onBattery, now: 0))
        let unconfirmed = closed(onBattery) { $0.flagConfirmed = false }
        XCTAssertNil(chime.observe(unconfirmed, now: 10))
        XCTAssertNil(chime.observe(unconfirmed, now: 11.4))
        XCTAssertEqual(chime.observe(unconfirmed, now: 11.5), .silent(.flagNotConfirmed))
        XCTAssertFalse(chime.isWaiting)
        XCTAssertNil(chime.observe(closed(onBattery), now: 12), "An answer after the wait starts no chime")
    }

    func testAnAnswerThatIsSeenLateIsNoChime() {
        var chime = LidChime()
        XCTAssertNil(chime.observe(onBattery, now: 0))
        XCTAssertNil(chime.observe(closed(onBattery) { $0.flagConfirmed = false }, now: 10))
        XCTAssertEqual(chime.observe(closed(onBattery), now: 13), .silent(.flagNotConfirmed))
    }

    func testTheWaitEndsWhenTheHoldEndsOrTheLidOpens() {
        var chime = LidChime()
        let unconfirmed = closed(onBattery) { $0.flagConfirmed = false }
        XCTAssertNil(chime.observe(onBattery, now: 0))
        XCTAssertNil(chime.observe(unconfirmed, now: 10))
        XCTAssertEqual(chime.observe(closed(onBattery) { $0.holding = false }, now: 10.5), .silent(.notHolding))
        XCTAssertFalse(chime.isWaiting)

        XCTAssertNil(chime.observe(onBattery, now: 20))
        XCTAssertNil(chime.observe(unconfirmed, now: 30))
        XCTAssertEqual(chime.observe(onBattery, now: 30.5), .silent(.reopened))
        XCTAssertFalse(chime.isWaiting)
        XCTAssertNil(chime.observe(onBattery, now: 31))
    }

    func testPowerThatComesDuringTheWaitChimes() {
        var chime = LidChime()
        XCTAssertNil(chime.observe(onBattery, now: 0))
        XCTAssertNil(chime.observe(closed(onBattery) { $0.flagConfirmed = false }, now: 10))
        XCTAssertEqual(chime.observe(closed(onPower) { $0.flagConfirmed = false }, now: 10.5), .played)
    }

    // MARK: What is no lid that closes

    func testNoChimeAtLaunchWithTheLidClosed() {
        var chime = LidChime()
        XCTAssertNil(chime.observe(closed(onPower), now: 0))
        XCTAssertNil(chime.observe(closed(onPower), now: 2))
        XCTAssertFalse(chime.isWaiting)
        // The lid opens and closes: that one counts.
        XCTAssertNil(chime.observe(onPower, now: 4))
        XCTAssertEqual(chime.observe(closed(onPower), now: 8), .played)
    }

    func testNoChimeAfterASleep() {
        var chime = LidChime()
        XCTAssertNil(chime.observe(onPower, now: 0))
        // The lid closed while the Mac slept.
        chime.forget()
        XCTAssertNil(chime.observe(closed(onPower), now: 10))
        XCTAssertNil(chime.observe(closed(onPower), now: 12))
    }

    func testASleepEndsTheWait() {
        var chime = LidChime()
        XCTAssertNil(chime.observe(onBattery, now: 0))
        XCTAssertNil(chime.observe(closed(onBattery) { $0.flagConfirmed = false }, now: 10))
        chime.forget()
        XCTAssertFalse(chime.isWaiting)
        XCTAssertNil(chime.observe(closed(onBattery), now: 10.5))
    }

    /// A display that is plugged or unplugged under a closed lid changes
    /// nothing the chime reads, and the power source alone is no lid.
    func testNoChimeWhenOnlyThePowerSourceChangesUnderAClosedLid() {
        var chime = LidChime()
        XCTAssertNil(chime.observe(onBattery, now: 0))
        XCTAssertEqual(chime.observe(closed(onBattery), now: 10), .played)
        XCTAssertNil(chime.observe(closed(onPower), now: 20))
        XCTAssertNil(chime.observe(closed(onBattery), now: 30))
        XCTAssertNil(chime.observe(closed(onBattery), now: 30.1))
    }

    func testAMacWithoutALidNeverChimes() {
        var chime = LidChime()
        for second in 0..<60 {
            XCTAssertNil(chime.observe(onPower, now: TimeInterval(second)))
        }
    }

    // MARK: A lid that bounces

    func testALidThatBouncesGivesOneChime() {
        var chime = LidChime()
        XCTAssertNil(chime.observe(onPower, now: 0))
        XCTAssertEqual(chime.observe(closed(onPower), now: 10), .played)
        XCTAssertNil(chime.observe(onPower, now: 10.2))
        XCTAssertEqual(chime.observe(closed(onPower), now: 10.4), .silent(.tooSoon))
        XCTAssertNil(chime.observe(onPower, now: 11))
        XCTAssertEqual(chime.observe(closed(onPower), now: 11.9), .silent(.tooSoon))
        // Opened and closed again by hand.
        XCTAssertNil(chime.observe(onPower, now: 12.5))
        XCTAssertEqual(chime.observe(closed(onPower), now: 13), .played)
    }

    func testALidThatClosesAndOpensAtOnceGivesAtMostOneChime() {
        var chime = LidChime()
        XCTAssertNil(chime.observe(onPower, now: 0))
        XCTAssertEqual(chime.observe(closed(onPower), now: 10), .played)
        XCTAssertNil(chime.observe(onPower, now: 11))
        XCTAssertNil(chime.observe(onPower, now: 13))
    }

    func testABounceDuringTheWaitGivesOneChime() {
        var chime = LidChime()
        let unconfirmed = closed(onBattery) { $0.flagConfirmed = false }
        XCTAssertNil(chime.observe(onBattery, now: 0))
        XCTAssertNil(chime.observe(unconfirmed, now: 10))
        XCTAssertEqual(chime.observe(onBattery, now: 10.1), .silent(.reopened))
        XCTAssertNil(chime.observe(unconfirmed, now: 10.2))
        XCTAssertEqual(chime.observe(closed(onBattery), now: 10.6), .played)
        XCTAssertNil(chime.observe(closed(onBattery), now: 11))
    }

    // MARK: The player

    func testTheChimerPlaysTheChosenSoundOnce() {
        let player = SilentPlayer()
        let chimer = LidChimer(player: player)
        chimer.observe(onBattery, sound: .purr, now: 0)
        XCTAssertEqual(chimer.observe(closed(onBattery), sound: .purr, now: 10), .played)
        chimer.observe(closed(onBattery), sound: .purr, now: 12)
        chimer.observe(closed(onBattery), sound: .purr, now: 14)
        XCTAssertEqual(player.played, [.purr])
    }

    func testTheChimerPlaysNothingWhenTheMacWillSleep() {
        let player = SilentPlayer()
        let chimer = LidChimer(player: player)
        chimer.observe(onBattery, sound: .tink, now: 0)
        XCTAssertEqual(
            chimer.observe(closed(onBattery) { $0.holding = false }, sound: .tink, detail: "Mac can sleep: no agent is open", now: 10),
            .silent(.notHolding)
        )
        chimer.observe(onBattery, sound: .tink, now: 20)
        chimer.observe(closed(onBattery) { $0.enabled = false }, sound: .tink, now: 30)
        XCTAssertEqual(player.played, [])
    }

    func testTheChimerPlaysWhenTheFlagComesAndNotBefore() {
        let player = SilentPlayer()
        let chimer = LidChimer(player: player)
        let unconfirmed = closed(onBattery) { $0.flagConfirmed = false }
        chimer.observe(onBattery, sound: .tink, now: 0)
        XCTAssertNil(chimer.observe(unconfirmed, sound: .tink, now: 10))
        XCTAssertTrue(chimer.isWaiting)
        XCTAssertEqual(player.played, [], "Never before the flag is confirmed")
        chimer.observe(unconfirmed, sound: .tink, now: 10.25)
        XCTAssertEqual(player.played, [])
        chimer.observe(closed(onBattery), sound: .tink, now: 10.5)
        XCTAssertEqual(player.played, [.tink])
        XCTAssertFalse(chimer.isWaiting)
    }

    func testAChimerWithoutAPlayerAndAMissingSoundDoNoHarm() {
        let none = LidChimer(player: nil)
        none.observe(onPower, sound: .tink, now: 0)
        XCTAssertEqual(none.observe(closed(onPower), sound: .tink, now: 10), .played)
        none.preview(.glass)

        let player = SilentPlayer()
        player.missing = true
        let chimer = LidChimer(player: player)
        chimer.observe(onPower, sound: .glass, now: 0)
        XCTAssertEqual(chimer.observe(closed(onPower), sound: .glass, now: 10), .played)
        chimer.preview(.bottle)
        XCTAssertEqual(player.played, [.glass, .bottle])
    }

    // MARK: The setting

    func testTheChimeIsOnWithGlassUnlessSaved() throws {
        XCTAssertTrue(DetectionSettings().chimeOnLidClose)
        XCTAssertEqual(DetectionSettings().lidChimeSound, .glass)
        let old = try JSONDecoder().decode(DetectionSettings.self, from: Data(#"{"waitingHold":60}"#.utf8))
        XCTAssertTrue(old.chimeOnLidClose, "On for settings of a build that did not have it")
        XCTAssertEqual(old.lidChimeSound, .glass)
        var settings = DetectionSettings()
        settings.chimeOnLidClose = false
        settings.lidChimeSound = .bottle
        let saved = try JSONDecoder().decode(DetectionSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(saved, settings)
        let unknown = try JSONDecoder().decode(DetectionSettings.self, from: Data(#"{"lidChimeSound":"Gong","chimeOnLidClose":false}"#.utf8))
        XCTAssertEqual(unknown.lidChimeSound, .glass, "A sound this build does not know is the default one")
        XCTAssertFalse(unknown.chimeOnLidClose)
    }

    func testTheSoundsHaveTheNamesOfTheSystemSounds() {
        XCTAssertEqual(LidChimeSound.allCases.map(\.rawValue), ["Tink", "Bottle", "Purr", "Glass"])
    }

    func testTheTextsNameTheLid() {
        XCTAssertEqual(PanelText.lidChimeSwitch, "Sound when the lid closes")
        XCTAssertEqual(PanelText.lidChimeExplained, "Plays only when your Mac stays awake. No sound means it sleeps.")
        XCTAssertEqual(LidChime.Outcome.played.logLine, "lid closed: the chime played")
        XCTAssertEqual(LidChime.Outcome.silent(.helperNotSetUp).logLine, "lid closed: no chime, on battery, and the helper is not set up")
    }
}
