import XCTest

@MainActor
final class DisplayControllerTests: XCTestCase {
    private final class Reader: DisplayReading {
        var inputs = DisplayInputs()
        var reads = 0

        func read() -> DisplayInputs {
            reads += 1
            return inputs
        }
    }

    private final class Sleeper: DisplaySleeping {
        var requests = 0
        var wakes = 0

        func sleepDisplays() -> Bool {
            requests += 1
            return true
        }

        func wakeDisplays() { wakes += 1 }
    }

    /// One way to set the brightness, over a panel the ways can share.
    private final class Method: BuiltinBrightness {
        final class Panel {
            var level: Float = 0.6
        }

        enum Kind {
            case works
            /// Says no.
            case refuses
            /// Says yes and changes nothing, as IOKit does on Apple silicon.
            case pretends
            case cannotRead
        }

        let name: String
        let kind: Kind
        let panel: Panel
        var sets: [Float] = []

        init(_ name: String, _ kind: Kind = .works, panel: Panel) {
            self.name = name
            self.kind = kind
            self.panel = panel
        }

        func level() -> Float? { kind == .cannotRead ? nil : panel.level }

        func set(_ level: Float) -> Bool {
            sets.append(level)
            switch kind {
            case .refuses: return false
            case .pretends: return true
            case .works, .cannotRead:
                panel.level = level
                return true
            }
        }
    }

    private final class Watcher: DisplayWatching {
        var onChange: ((Bool?) -> Void)?
        var stopped = false

        func start(onChange: @escaping (Bool?) -> Void) { self.onChange = onChange }
        func stop() { stopped = true }
    }

    private final class Lid: LidAngleReading {
        var isAvailable = true
        var degrees: Double? = 110
        var onPush: ((Double) -> Void)?
        var reads = 0

        func start(onPush: @escaping (Double) -> Void) { self.onPush = onPush }
        func stop() { onPush = nil }

        func angle() -> Double? {
            reads += 1
            return onPush == nil ? nil : degrees
        }
    }

    private final class Ticker: LidTicking {
        var interval: TimeInterval?
        var work: (() -> Void)?

        func tick(every interval: TimeInterval?, _ work: @escaping () -> Void) {
            self.interval = interval
            self.work = interval == nil ? nil : work
        }
    }

    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_791_200_000)
    }

    private var defaults: UserDefaults!
    private var suite = ""
    private let panel = Method.Panel()
    private let reader = Reader()
    private let sleeper = Sleeper()
    private let start = Date(timeIntervalSince1970: 1_791_200_000)

    override func setUp() {
        suite = "caffeinagent-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private let lid = Lid()
    /// The timer and the sensor hold the controller weakly.
    private var kept: DisplayController?
    private let ticker = Ticker()
    private let clock = Clock()

    private func controller(_ methods: [Method], watcher: Watcher? = nil) -> DisplayController {
        DisplayController(reader: reader, sleeper: sleeper, dimmer: BuiltinDimmer(methods: methods, defaults: defaults), watcher: watcher)
    }

    /// With the lid angle sensor, and agent caffeine holding.
    private func fading(watcher: Watcher? = nil) -> DisplayController {
        let controller = DisplayController(
            reader: reader, sleeper: sleeper, dimmer: BuiltinDimmer(methods: [Method("first", panel: panel)], defaults: defaults),
            watcher: watcher, lid: lid, ticker: ticker, clock: { [clock] in clock.now }
        )
        controller.start(onChange: {})
        controller.update(lidClosed: false, holding: true, enabled: true, fade: true, now: clock.now)
        kept = controller
        return controller
    }

    /// The timer fires: the lid is at this angle, one frame later.
    private func tick(_ degrees: Double?, after seconds: TimeInterval = 1.0 / 60) {
        clock.now += seconds
        lid.degrees = degrees
        ticker.work?()
    }

    private func move(from: Double, to: Double, over seconds: TimeInterval) {
        let frames = Int(seconds * 60)
        for frame in 1...frames { tick((from + (to - from) * Double(frame) / Double(frames)).rounded()) }
    }

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private var saved: Double? { defaults.object(forKey: BuiltinDimmer.previousKey) as? Double }

    // MARK: The dimmer

    func testDimSavesTheBrightnessFirstAndRestorePutsItBack() {
        let method = Method("first", panel: panel)
        let dimmer = BuiltinDimmer(methods: [method], defaults: defaults)
        XCTAssertFalse(dimmer.isDimmed)
        XCTAssertTrue(dimmer.dim())
        XCTAssertEqual(panel.level, 0)
        XCTAssertEqual(saved ?? -1, 0.6, accuracy: 0.001)
        XCTAssertTrue(dimmer.isDimmed)
        XCTAssertTrue(dimmer.restore())
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertNil(saved)
        XCTAssertFalse(dimmer.isDimmed)
        XCTAssertTrue(dimmer.restore(), "Nothing to put back is no failure")
        XCTAssertEqual(method.sets.count, 2)
    }

    func testTheWaysAreTriedInOrderAndTheOneThatWorkedIsRemembered() {
        let refuses = Method("refuses", .refuses, panel: panel)
        let pretends = Method("pretends", .pretends, panel: panel)
        let works = Method("works", panel: panel)
        let dimmer = BuiltinDimmer(methods: [refuses, pretends, works], defaults: defaults)
        XCTAssertTrue(dimmer.dim())
        XCTAssertEqual([refuses.sets, pretends.sets, works.sets], [[0], [0], [0]])
        XCTAssertEqual(defaults.string(forKey: BuiltinDimmer.methodKey), "works")
        XCTAssertTrue(dimmer.restore())
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertEqual(refuses.sets.count, 1, "The way that worked comes first from now on")
        XCTAssertEqual(works.sets.count, 2)
    }

    func testADimThatNoWayCanDoLeavesNothingBehind() {
        let dimmer = BuiltinDimmer(methods: [Method("refuses", .refuses, panel: panel), Method("pretends", .pretends, panel: panel)], defaults: defaults)
        XCTAssertFalse(dimmer.dim())
        XCTAssertEqual(panel.level, 0.6)
        XCTAssertFalse(dimmer.isDimmed)
    }

    func testABrightnessThatCannotBeReadIsNotTouched() {
        let method = Method("blind", .cannotRead, panel: panel)
        let dimmer = BuiltinDimmer(methods: [method], defaults: defaults)
        XCTAssertFalse(dimmer.dim(), "Without the old value there is nothing to put back")
        XCTAssertEqual(method.sets, [])
        XCTAssertFalse(dimmer.isDimmed)
    }

    func testADisplayThatIsDarkAlreadyIsNotMarked() {
        panel.level = 0
        let dimmer = BuiltinDimmer(methods: [Method("first", panel: panel)], defaults: defaults)
        XCTAssertTrue(dimmer.dim())
        XCTAssertFalse(dimmer.isDimmed)
    }

    func testASecondDimKeepsTheFirstValue() {
        let dimmer = BuiltinDimmer(methods: [Method("first", panel: panel)], defaults: defaults)
        XCTAssertTrue(dimmer.dim())
        // macOS raised the brightness in between.
        panel.level = 0.3
        XCTAssertTrue(dimmer.dim())
        XCTAssertEqual(panel.level, 0)
        XCTAssertTrue(dimmer.restore())
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
    }

    // MARK: The controller

    func testWithTheLidOpenNothingIsRead() {
        let controller = controller([Method("first", panel: panel)])
        controller.update(lidClosed: false, holding: true, enabled: true, now: at(0))
        XCTAssertEqual(reader.reads, 0)
        XCTAssertEqual(sleeper.requests, 0)
    }

    func testLidClosedWithoutAnExternalDisplaySleepsTheDisplaysOncePerFiveSeconds() {
        let controller = controller([Method("first", panel: panel)])
        for seconds in [0.0, 2, 4] { controller.update(lidClosed: true, holding: true, enabled: true, now: at(seconds)) }
        XCTAssertEqual(sleeper.requests, 1)
        XCTAssertEqual(panel.level, 0.6, "Not dimmed while display sleep may still hold")
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(6))
        XCTAssertEqual(sleeper.requests, 2)
        XCTAssertEqual(panel.level, 0, "It did not hold: dimmed as well")
        // The lid opens: the brightness is back, and nothing sleeps.
        controller.update(lidClosed: false, holding: true, enabled: true, now: at(60))
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertEqual(sleeper.requests, 2)
        XCTAssertNil(saved)
    }

    func testLidClosedNextToAnExternalDisplayOnlyDimsTheBuiltInOne() {
        reader.inputs.externalDisplay = true
        let controller = controller([Method("first", panel: panel)])
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(0))
        XCTAssertEqual(sleeper.requests, 0)
        XCTAssertEqual(panel.level, 0)
        XCTAssertEqual(saved ?? -1, 0.6, accuracy: 0.001)
        // The hold ends at the desk: it stays dark until the lid opens.
        controller.update(lidClosed: true, holding: false, enabled: true, now: at(10))
        XCTAssertEqual(panel.level, 0)
        controller.update(lidClosed: false, holding: false, enabled: true, now: at(20))
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertEqual(sleeper.requests, 0)
    }

    func testNothingHappensWhenNotHoldingOrWithTheSettingOff() {
        let controller = controller([Method("first", panel: panel)])
        controller.update(lidClosed: true, holding: false, enabled: true, now: at(0))
        controller.update(lidClosed: true, holding: true, enabled: false, now: at(10))
        XCTAssertEqual(sleeper.requests, 0)
        XCTAssertEqual(panel.level, 0.6)
    }

    func testQuitPutsTheBrightnessBack() {
        reader.inputs.externalDisplay = true
        let watcher = Watcher()
        let controller = controller([Method("first", panel: panel)], watcher: watcher)
        controller.start(onChange: {})
        XCTAssertNotNil(watcher.onChange)
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(0))
        XCTAssertEqual(panel.level, 0)
        controller.stop()
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertTrue(watcher.stopped)
        XCTAssertNil(saved)
    }

    /// The app crashed while the display was dark: the next start puts the
    /// brightness back before anything else.
    func testAStartAfterACrashPutsTheBrightnessBackFirst() {
        defaults.set(0.45, forKey: BuiltinDimmer.previousKey)
        panel.level = 0
        let controller = controller([Method("first", panel: panel)])
        controller.start(onChange: {})
        XCTAssertEqual(panel.level, 0.45, accuracy: 0.001)
        XCTAssertNil(saved)
    }

    func testARestoreThatFailsIsTriedAgain() {
        reader.inputs.externalDisplay = true
        let dims = Method("dims", panel: panel)
        let controller = controller([dims])
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(0))
        XCTAssertEqual(panel.level, 0)
        // The display is away for a moment while the lid opens.
        let blocked = DisplayController(
            reader: reader, sleeper: sleeper, dimmer: BuiltinDimmer(methods: [Method("refuses", .refuses, panel: panel)], defaults: defaults)
        )
        blocked.start(onChange: {})
        XCTAssertEqual(saved ?? -1, 0.6, accuracy: 0.001, "The value stays saved until it is back")
        blocked.update(lidClosed: false, holding: false, enabled: true, now: at(10))
        XCTAssertNotNil(saved)
        controller.update(lidClosed: false, holding: false, enabled: true, now: at(12))
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertNil(saved)
    }

    // MARK: The lid angle

    func testTheDimmerSetsALevelWithoutTouchingTheSavedValue() {
        let pretends = Method("pretends", .pretends, panel: panel)
        let works = Method("works", panel: panel)
        let dimmer = BuiltinDimmer(methods: [Method("refuses", .refuses, panel: panel), pretends, works], defaults: defaults)
        XCTAssertNil(dimmer.saved)
        dimmer.save(0.6)
        XCTAssertTrue(dimmer.set(0.3))
        XCTAssertEqual(panel.level, 0.3)
        XCTAssertEqual(dimmer.saved, 0.6)
        XCTAssertTrue(dimmer.set(0.2))
        XCTAssertEqual(pretends.sets.count, 1, "The way that was seen to work is used from then on")
        XCTAssertTrue(dimmer.restore())
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertFalse(BuiltinDimmer(methods: [pretends], defaults: defaults).set(0.1))
    }

    func testTheSensorIsAskedOnlyWhileAgentCaffeineHoldsAndTheFadeIsOn() {
        let controller = controller([Method("first", panel: panel)])
        controller.update(lidClosed: false, holding: true, enabled: true, fade: true, now: clock.now)
        XCTAssertNil(lid.onPush, "A controller without a sensor asks none")

        let withLid = DisplayController(
            reader: reader, sleeper: sleeper, dimmer: BuiltinDimmer(methods: [Method("first", panel: panel)], defaults: defaults),
            lid: lid, ticker: ticker, clock: { [clock] in clock.now }
        )
        XCTAssertTrue(withLid.hasLidAngleSensor)
        withLid.update(lidClosed: false, holding: false, enabled: true, fade: true, now: clock.now)
        withLid.update(lidClosed: false, holding: true, enabled: true, fade: false, now: clock.now)
        withLid.update(lidClosed: false, holding: true, enabled: false, fade: true, now: clock.now)
        XCTAssertNil(lid.onPush)
        XCTAssertNil(ticker.interval)
        withLid.update(lidClosed: false, holding: true, enabled: true, fade: true, now: clock.now)
        XCTAssertNotNil(lid.onPush)
        XCTAssertEqual(ticker.interval, LidPoll.slow.interval)
        XCTAssertEqual(reader.reads, 0, "With the lid wide open only the angle is read")
        withLid.update(lidClosed: false, holding: false, enabled: true, fade: true, now: clock.now)
        XCTAssertNil(lid.onPush, "The hold ended with the lid open")
        XCTAssertNil(ticker.interval)
    }

    func testAMacWithoutTheSensorNeverStartsIt() {
        lid.isAvailable = false
        let controller = fading()
        XCTAssertFalse(controller.hasLidAngleSensor)
        XCTAssertNil(ticker.interval)
        XCTAssertEqual(lid.reads, 0)
        // The old way still works.
        controller.update(lidClosed: true, holding: true, enabled: true, fade: true, now: clock.now)
        XCTAssertEqual(sleeper.requests, 1)
    }

    func testTheBrightnessFollowsTheLidInTheSameTick() {
        _ = fading()
        tick(69, after: 0.5)
        XCTAssertEqual(ticker.interval, LidPoll.fast.interval)
        move(from: 69, to: 30, over: 0.5)
        XCTAssertEqual(panel.level, 0.6 * Float(LidDimming.curve(30)), accuracy: 0.01)
        XCTAssertEqual(saved ?? -1, 0.6, accuracy: 0.001)
        tick(24)
        XCTAssertEqual(panel.level, 0.3, accuracy: 0.01, "No sample of the engine in between")
        move(from: 24, to: 0, over: 0.3)
        XCTAssertEqual(panel.level, 0)
        XCTAssertEqual(sleeper.requests, 1)
        // The lid opens.
        tick(5, after: 3)
        XCTAssertEqual(sleeper.wakes, 1)
        XCTAssertGreaterThan(panel.level, 0)
        move(from: 5, to: 50, over: 0.5)
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertNil(saved)
        XCTAssertEqual(sleeper.wakes, 1)
    }

    func testAnAngleTheSensorSendsByItselfIsActedOnAtOnce() {
        _ = fading()
        clock.now += 0.1
        lid.onPush?(0)
        XCTAssertEqual(panel.level, 0)
        XCTAssertEqual(sleeper.requests, 1)
    }

    func testASampleOfTheEngineDoesNotPutTheBrightnessBackInTheMiddleOfAFade() {
        let controller = fading()
        tick(60, after: 0.5)
        move(from: 60, to: 0, over: 0.5)
        // The clamshell switch says closed, then open at a few degrees.
        controller.update(lidClosed: true, holding: true, enabled: true, fade: true, now: clock.now)
        tick(10, after: 2)
        let dim = panel.level
        controller.update(lidClosed: false, holding: true, enabled: true, fade: true, now: clock.now)
        XCTAssertEqual(panel.level, dim, accuracy: 0.01, "The angle decides, not the switch")
        XCTAssertLessThan(panel.level, 0.1)
        XCTAssertNotNil(saved)
    }

    func testNextToAnExternalDisplayTheFadeDoesNotSleepTheDisplays() {
        reader.inputs.externalDisplay = true
        _ = fading()
        tick(60, after: 0.5)
        move(from: 60, to: 0, over: 0.5)
        XCTAssertEqual(panel.level, 0)
        XCTAssertEqual(sleeper.requests, 0)
    }

    func testSwitchingTheFadeOffInTheMiddlePutsTheBrightnessBackAndStopsTheSensor() {
        let controller = fading()
        tick(60, after: 0.5)
        move(from: 60, to: 20, over: 0.5)
        XCTAssertLessThan(panel.level, 0.3)
        controller.update(lidClosed: false, holding: true, enabled: true, fade: false, now: clock.now)
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertNil(saved)
        XCTAssertNil(lid.onPush)
        XCTAssertNil(ticker.interval)
    }

    func testAHoldThatEndsInTheMiddleKeepsTheSensorUntilTheLidIsUp() {
        let controller = fading()
        tick(60, after: 0.5)
        move(from: 60, to: 20, over: 0.5)
        controller.update(lidClosed: false, holding: false, enabled: true, fade: true, now: clock.now)
        XCTAssertNotNil(lid.onPush)
        move(from: 20, to: 50, over: 0.5)
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        controller.update(lidClosed: false, holding: false, enabled: true, fade: true, now: clock.now)
        XCTAssertNil(lid.onPush)
    }

    func testQuitInTheMiddleOfAFadePutsTheBrightnessBack() {
        let controller = fading()
        tick(60, after: 0.5)
        move(from: 60, to: 20, over: 0.5)
        controller.stop()
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertNil(saved)
        XCTAssertNil(lid.onPush)
        XCTAssertNil(ticker.interval)
    }

    func testASensorThatDiesInTheMiddleOfAFadePutsTheBrightnessBack() {
        _ = fading()
        tick(60, after: 0.5)
        move(from: 60, to: 20, over: 0.5)
        tick(nil, after: 0.2)
        tick(nil, after: 0.2)
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertNil(saved)
    }

    // MARK: Without the fade: at once, not at the next sample

    func testTheLidThatClosesIsActedOnWhenTheSwitchSaysSo() {
        let watcher = Watcher()
        var samples = 0
        let controller = controller([Method("first", panel: panel)], watcher: watcher)
        controller.start { samples += 1 }
        controller.update(lidClosed: false, holding: true, enabled: true, now: at(0))
        watcher.onChange?(true)
        XCTAssertEqual(sleeper.requests, 1, "No sample of the engine was needed")
        XCTAssertEqual(samples, 1, "One is asked for, for the rest of the app")
        watcher.onChange?(false)
        XCTAssertEqual(sleeper.wakes, 1)
    }

    func testTheLidThatOpensGetsItsBrightnessBackWhenTheSwitchSaysSo() {
        reader.inputs.externalDisplay = true
        let watcher = Watcher()
        let controller = controller([Method("first", panel: panel)], watcher: watcher)
        controller.start(onChange: {})
        controller.update(lidClosed: false, holding: true, enabled: true, now: at(0))
        watcher.onChange?(true)
        XCTAssertEqual(panel.level, 0)
        watcher.onChange?(false)
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertNil(saved)
        // The list of displays changed: the lid is as it was.
        watcher.onChange?(nil)
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
    }
}
