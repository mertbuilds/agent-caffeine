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
        var reads = 0

        init(_ name: String, _ kind: Kind = .works, panel: Panel) {
            self.name = name
            self.kind = kind
            self.panel = panel
        }

        func level() -> Float? {
            reads += 1
            return kind == .cannotRead ? nil : panel.level
        }

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

    /// A way whose set call does not come back until it is let go, as a
    /// WindowServer that hangs.
    private final class Hanging: BuiltinBrightness {
        let name = "hanging"
        private let gate = DispatchGroup()
        private let lock = NSLock()
        private var count = 0
        private var released = false
        private var written: [Float] = []
        var calls: Int { lock.withLock { count } }
        /// Every set call, in the order they started.
        var sets: [Float] { lock.withLock { written } }

        init() { gate.enter() }

        /// The set calls come back, from now on at once.
        func letGo() {
            lock.withLock {
                guard !released else { return }
                released = true
                gate.leave()
            }
        }

        func level() -> Float? {
            lock.withLock { count += 1 }
            return 0.6
        }

        func set(_ level: Float) -> Bool {
            lock.withLock {
                count += 1
                written.append(level)
            }
            gate.wait()
            return true
        }
    }

    /// Waits until the calls queued before this are done.
    private func drain(_ calls: DisplayCalls) {
        let done = expectation(description: "the queue is done")
        calls.enqueue { done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    /// Next to an external display the lid closes, and the write of zero hangs.
    private func hungDim() -> (DisplayController, Hanging, DisplayCalls) {
        let hanging = Hanging()
        let calls = DisplayCalls(limit: 0.05)
        reader.inputs.externalDisplay = true
        let controller = DisplayController(
            reader: reader, sleeper: sleeper, dimmer: BuiltinDimmer(methods: [hanging], defaults: defaults, calls: calls), settle: delay
        )
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(0))
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(DisplayController.settleTime))
        XCTAssertTrue(calls.isOff)
        XCTAssertEqual(hanging.sets, [0])
        XCTAssertEqual(saved ?? -1, 0.6, accuracy: 0.001)
        return (controller, hanging, calls)
    }

    private final class Watcher: DisplayWatching {
        var onChange: ((DisplayChange) -> Void)?
        var stopped = false

        func start(onChange: @escaping (DisplayChange) -> Void) { self.onChange = onChange }
        func stop() { stopped = true }
    }

    private final class Delay: DisplayDelaying {
        var seconds: TimeInterval?
        var work: (() -> Void)?

        func after(_ seconds: TimeInterval?, _ work: @escaping () -> Void) {
            self.seconds = seconds
            self.work = seconds == nil ? nil : work
        }

        /// The time is up.
        func fire() {
            let work = self.work
            seconds = nil
            self.work = nil
            work?()
        }
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
    private let panel = Method.Panel()
    private let reader = Reader()
    private let sleeper = Sleeper()
    private let start = Date(timeIntervalSince1970: 1_791_200_000)

    override func setUp() {
        defaults = TestDefaults()
    }

    private let lid = Lid()
    /// The timer and the sensor hold the controller weakly.
    private var kept: DisplayController?
    private let ticker = Ticker()
    private let delay = Delay()
    private let clock = Clock()

    private func controller(_ methods: [Method], watcher: Watcher? = nil) -> DisplayController {
        DisplayController(
            reader: reader, sleeper: sleeper, dimmer: BuiltinDimmer(methods: methods, defaults: defaults), watcher: watcher, settle: delay,
            clock: { [clock] in clock.now }
        )
    }

    /// The way the fade sets the brightness with.
    private lazy var first = Method("first", panel: panel)

    /// With the lid angle sensor, and Agent Caffeine holding.
    private func fading(watcher: Watcher? = nil) -> DisplayController {
        let controller = DisplayController(
            reader: reader, sleeper: sleeper, dimmer: BuiltinDimmer(methods: [first], defaults: defaults),
            watcher: watcher, lid: lid, ticker: ticker, settle: delay, clock: { [clock] in clock.now }
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

    /// An older version remembered `CoreDisplay`, which is gone.
    func testAWayThatWasRememberedAndIsGoneIsLeftOut() {
        defaults.set("CoreDisplay", forKey: BuiltinDimmer.methodKey)
        let method = Method("DisplayServices", panel: panel)
        XCTAssertTrue(BuiltinDimmer(methods: [method], defaults: defaults).dim())
        XCTAssertEqual(method.sets, [0])
        XCTAssertEqual(defaults.string(forKey: BuiltinDimmer.methodKey), "DisplayServices")
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

    // MARK: Calls that hang

    func testTheCallsRunOneAfterTheOtherInOrder() {
        let calls = DisplayCalls()
        var order: [Int] = []
        for index in 0..<50 { XCTAssertEqual(calls.run("call") { order.append(index); return index }, index) }
        XCTAssertEqual(order, Array(0..<50))
        XCTAssertFalse(calls.isOff)
        XCTAssertEqual(DisplayCalls.limit, 0.2)
    }

    func testACallThatHangsTurnsTheDisplayFeatureOffAndTheMainThreadGoesOn() {
        let hanging = Hanging()
        defer { hanging.letGo() }
        let calls = DisplayCalls(limit: 0.05)
        reader.inputs.externalDisplay = true
        let controller = DisplayController(
            reader: reader, sleeper: sleeper, dimmer: BuiltinDimmer(methods: [hanging], defaults: defaults, calls: calls),
            lid: lid, ticker: ticker, settle: delay, clock: { [clock] in clock.now }
        )
        kept = controller
        let started = Date()
        controller.update(lidClosed: true, holding: true, enabled: true, fade: true, now: clock.now)
        controller.update(lidClosed: true, holding: true, enabled: true, fade: true, now: clock.now + DisplayController.settleTime)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "Not stuck in the call")
        XCTAssertTrue(calls.isOff)
        let made = hanging.calls
        // Nothing more is asked of the displays: no brightness, no sleep.
        reader.inputs.externalDisplay = false
        for seconds in stride(from: 2.0, through: 600, by: 2) {
            controller.update(lidClosed: true, holding: true, enabled: true, fade: true, now: clock.now + seconds)
        }
        controller.update(lidClosed: false, holding: true, enabled: true, fade: true, now: clock.now + 700)
        controller.willSleep()
        controller.stop()
        XCTAssertEqual(hanging.calls, made)
        XCTAssertEqual(sleeper.requests, 0)
        XCTAssertNil(lid.onPush, "The sensor is closed")
        XCTAssertNil(ticker.interval)
        XCTAssertNotNil(saved, "Nothing is written while the call hangs")
        XCTAssertNil(calls.run("read") { 1 })
        hanging.letGo()
        drain(calls)
        XCTAssertEqual(hanging.sets.last, 0.6, "Once the call returns, the brightness comes back")
        XCTAssertNil(saved)
    }

    /// After a call that hung, a panel at zero must not wait for the next
    /// start: on Apple silicon that is a black screen.
    func testAfterACallThatHungTheBrightnessIsQueuedWhenTheLidOpens() {
        let (controller, hanging, calls) = hungDim()
        defer { hanging.letGo() }
        let started = Date()
        controller.update(lidClosed: false, holding: true, enabled: true, now: at(10))
        controller.update(lidClosed: false, holding: true, enabled: true, now: at(12))
        controller.willSleep()
        controller.stop()
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5, "The main thread does not wait")
        XCTAssertEqual(hanging.sets, [0], "Not before the hung call returns")
        XCTAssertNotNil(saved)
        hanging.letGo()
        drain(calls)
        XCTAssertEqual(hanging.sets, [0, 0.6], "One write")
        XCTAssertNil(saved)
    }

    func testAfterACallThatHungTheBrightnessIsQueuedUnderTheShutLidOnlyAtSleepOrQuit() {
        let (controller, hanging, calls) = hungDim()
        defer { hanging.letGo() }
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(10))
        controller.update(holding: false, now: at(11))
        hanging.letGo()
        drain(calls)
        XCTAssertEqual(hanging.sets, [0], "Under the shut lid the display stays dark")
        controller.willSleep()
        drain(calls)
        XCTAssertEqual(hanging.sets, [0, 0.6])
        XCTAssertNil(saved)
        controller.stop()
        drain(calls)
        XCTAssertEqual(hanging.sets, [0, 0.6])
    }

    func testAfterACallThatHungQuitQueuesTheBrightness() {
        let (controller, hanging, calls) = hungDim()
        controller.stop()
        hanging.letGo()
        drain(calls)
        XCTAssertEqual(hanging.sets, [0, 0.6])
        XCTAssertNil(saved)
    }

    func testADisplaySleepThatHangsTurnsTheFeatureOff() {
        final class Stuck: DisplaySleeping {
            let release = DispatchSemaphore(value: 0)
            func sleepDisplays() -> Bool {
                release.wait()
                return true
            }
            func wakeDisplays() {}
        }
        let stuck = Stuck()
        defer { stuck.release.signal() }
        let calls = DisplayCalls(limit: 0.05)
        let method = Method("first", panel: panel)
        let controller = DisplayController(
            reader: reader, sleeper: stuck, dimmer: BuiltinDimmer(methods: [method], defaults: defaults, calls: calls), settle: delay
        )
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(0))
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(15))
        XCTAssertTrue(calls.isOff)
        let reads = method.reads
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(21))
        XCTAssertEqual(method.reads, reads)
        XCTAssertEqual(method.sets, [], "Not dimmed either")
    }

    // MARK: The controller

    func testWithTheLidOpenNothingIsRead() {
        let controller = controller([Method("first", panel: panel)])
        controller.update(lidClosed: false, holding: true, enabled: true, now: at(0))
        XCTAssertEqual(reader.reads, 0)
        XCTAssertEqual(sleeper.requests, 0)
    }

    func testLidClosedWithoutAnExternalDisplayAsksForDisplaySleepOnlyLateAndTwiceAtMost() {
        let controller = controller([Method("first", panel: panel)])
        for seconds in [0.0, 2, 4, 10, 14] { controller.update(lidClosed: true, holding: true, enabled: true, now: at(seconds)) }
        XCTAssertEqual(sleeper.requests, 0, "macOS turns the panel off by itself")
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(15))
        XCTAssertEqual(sleeper.requests, 1)
        XCTAssertEqual(panel.level, 0.6, "Not dimmed while display sleep may still hold")
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(21))
        XCTAssertEqual(sleeper.requests, 2)
        XCTAssertEqual(panel.level, 0, "It did not hold: dimmed as well")
        for seconds in stride(from: 23.0, through: 600, by: 2) { controller.update(lidClosed: true, holding: true, enabled: true, now: at(seconds)) }
        XCTAssertEqual(sleeper.requests, 2)
        // The lid opens: the brightness is back, and nothing sleeps.
        controller.update(lidClosed: false, holding: true, enabled: true, now: at(660))
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertEqual(sleeper.requests, 2)
        XCTAssertNil(saved)
    }

    func testLidClosedNextToAnExternalDisplayOnlyDimsTheBuiltInOne() {
        reader.inputs.externalDisplay = true
        let controller = controller([Method("first", panel: panel)])
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(0))
        XCTAssertEqual(panel.level, 0.6, "Not while macOS changes the displays for the closed lid")
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(DisplayController.settleTime))
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
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(2))
        XCTAssertEqual(panel.level, 0)
        controller.stop()
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertTrue(watcher.stopped)
        XCTAssertNil(saved)
    }

    // MARK: A stop and a sleep

    /// A safety stop ends the hold between two samples. The brightness
    /// comes back with the decision, before the Mac goes to sleep.
    func testAHoldThatAStopEndsGivesTheBrightnessBackAtOnce() {
        let controller = controller([Method("first", panel: panel)])
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(0))
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(15))
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(21))
        XCTAssertEqual(panel.level, 0, "Display sleep did not hold, so the display was dimmed")
        controller.update(holding: false, now: at(22))
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertNil(saved)
        // The same hold again changes nothing.
        let reads = reader.reads
        controller.update(holding: false, now: at(23))
        XCTAssertEqual(reader.reads, reads)
    }

    /// Lid closed on battery without the helper: the display fades to
    /// black and the Mac sleeps all the same. The brightness is back
    /// before it sleeps, with or without the app at the wake.
    func testTheBrightnessIsBackBeforeTheMacSleepsInTheMiddleOfAFade() {
        let controller = fading()
        tick(60, after: 0.5)
        move(from: 60, to: 0, over: 0.5)
        XCTAssertEqual(panel.level, 0)
        XCTAssertNotNil(saved)
        controller.willSleep()
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertNil(saved)
        XCTAssertNil(lid.onPush, "The sensor is not asked any more")
        XCTAssertNil(ticker.interval)
        // A sample that still comes before the Mac sleeps dims nothing.
        let requests = sleeper.requests
        controller.update(lidClosed: true, holding: true, enabled: true, fade: true, now: clock.now)
        lid.onPush?(0)
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertNil(saved)
        XCTAssertEqual(sleeper.requests, requests)
    }

    func testAfterTheWakeTheFadeStartsFromNewReadings() {
        let controller = fading()
        tick(60, after: 0.5)
        move(from: 60, to: 0, over: 0.5)
        controller.willSleep()
        // The user set another brightness, and the lid is open at the wake.
        panel.level = 0.8
        lid.degrees = 100
        controller.didWake()
        clock.now += 3600
        controller.update(lidClosed: false, holding: true, enabled: true, fade: true, now: clock.now)
        XCTAssertEqual(panel.level, 0.8, accuracy: 0.001)
        XCTAssertNil(saved)
        tick(60, after: 0.5)
        move(from: 60, to: 0, over: 0.5)
        XCTAssertEqual(panel.level, 0)
        XCTAssertEqual(saved ?? -1, 0.8, accuracy: 0.001, "The value from after the wake, not the one from before the sleep")
        move(from: 0, to: 50, over: 0.5)
        XCTAssertEqual(panel.level, 0.8, accuracy: 0.001)
    }

    /// The Mac did not sleep after all, and the lid is still shut.
    func testAfterTheWakeAShutLidIsDarkAgainFromTheBrightnessThatWasPutBack() {
        let controller = fading()
        tick(60, after: 0.5)
        move(from: 60, to: 0, over: 0.5)
        controller.willSleep()
        controller.didWake()
        lid.degrees = 0
        controller.update(lidClosed: true, holding: true, enabled: true, fade: true, now: clock.now)
        XCTAssertEqual(panel.level, 0)
        XCTAssertEqual(saved ?? -1, 0.6, accuracy: 0.001)
    }

    func testTheBrightnessIsBackBeforeTheMacSleepsNextToAnExternalDisplay() {
        reader.inputs.externalDisplay = true
        let watcher = Watcher()
        let controller = controller([Method("first", panel: panel)], watcher: watcher)
        controller.start(onChange: {})
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(0))
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(2))
        XCTAssertEqual(panel.level, 0)
        controller.willSleep()
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertNil(saved)
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(10))
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001, "Not dark again before the wake")
        // The lid opens with no word of a wake, and closes again.
        watcher.onChange?(.lid(closed: false))
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(20))
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(22))
        XCTAssertEqual(panel.level, 0)
    }

    func testARestoreThatFailedBeforeTheSleepIsTriedAgain() {
        reader.inputs.externalDisplay = true
        defaults.set(0.45, forKey: BuiltinDimmer.previousKey)
        panel.level = 0
        let refuses = DisplayController(
            reader: reader, sleeper: sleeper, dimmer: BuiltinDimmer(methods: [Method("refuses", .refuses, panel: panel)], defaults: defaults)
        )
        refuses.willSleep()
        XCTAssertNotNil(saved, "The value stays saved until it is back")
        let works = controller([Method("first", panel: panel)])
        works.willSleep()
        XCTAssertEqual(panel.level, 0.45, accuracy: 0.001)
        XCTAssertNil(saved)
    }

    func testPuttingTheBrightnessBackNeverMakesTheDisplayDarker() {
        let method = Method("first", panel: panel)
        let dimmer = BuiltinDimmer(methods: [method], defaults: defaults)
        dimmer.save(0.3)
        panel.level = 0.9
        XCTAssertTrue(dimmer.restore())
        XCTAssertEqual(panel.level, 0.9)
        XCTAssertEqual(method.sets, [], "Nothing is written")
        XCTAssertNil(saved)
        // Below the saved value it is written.
        dimmer.save(0.3)
        panel.level = 0.1
        XCTAssertTrue(dimmer.restore())
        XCTAssertEqual(panel.level, 0.3, accuracy: 0.001)
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
        controller.update(lidClosed: true, holding: true, enabled: true, now: at(2))
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
        controller.update(lidClosed: true, holding: true, enabled: true, fade: true, now: clock.now + 15)
        XCTAssertEqual(sleeper.requests, 1)
    }

    func testTheBrightnessFollowsTheLidInTheSameTick() {
        _ = fading()
        tick(69, after: 0.5)
        XCTAssertEqual(ticker.interval, LidPoll.fast.interval)
        move(from: 69, to: 30, over: 0.5)
        XCTAssertEqual(panel.level, 0.6 * Float(LidDimming.curve(30)), accuracy: 0.01)
        XCTAssertEqual(saved ?? -1, 0.6, accuracy: 0.001)
        for _ in 0..<12 { tick(24) }
        XCTAssertEqual(panel.level, 0.3, accuracy: 0.01, "No sample of the engine in between")
        move(from: 24, to: 0, over: 0.3)
        XCTAssertEqual(panel.level, 0)
        XCTAssertEqual(sleeper.requests, 0, "macOS turns the panel off by itself")
        // The lid opens.
        tick(5, after: 3)
        XCTAssertGreaterThan(panel.level, 0)
        move(from: 5, to: 50, over: 0.5)
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertNil(saved)
        XCTAssertEqual(sleeper.wakes, 0, "Nothing was put to sleep")
    }

    func testAnAngleTheSensorSendsByItselfIsActedOnAtOnce() {
        _ = fading()
        clock.now += 0.1
        lid.onPush?(0)
        XCTAssertEqual(panel.level, 0)
        XCTAssertEqual(sleeper.requests, 0)
    }

    func testASampleOfTheEngineDoesNotPutTheBrightnessBackInTheMiddleOfAFade() {
        let controller = fading()
        tick(60, after: 0.5)
        move(from: 60, to: 10, over: 0.5)
        let dim = panel.level
        controller.update(lidClosed: false, holding: true, enabled: true, fade: true, now: clock.now)
        XCTAssertEqual(panel.level, dim, accuracy: 0.01, "The angle decides")
        XCTAssertLessThan(panel.level, 0.1)
        XCTAssertNotNil(saved)
    }

    /// The lid switch ends the fade. While the lid stays shut nothing is
    /// read or written, and on open the brightness comes back in one step
    /// once the panel is on.
    func testUnderTheShutLidTheSensorIsClosedAndNothingIsReadOrWritten() {
        let watcher = Watcher()
        let controller = fading(watcher: watcher)
        tick(60, after: 0.5)
        move(from: 60, to: 0, over: 0.5)
        watcher.onChange?(.lid(closed: true))
        XCTAssertNil(lid.onPush, "The sensor is closed")
        XCTAssertNil(ticker.interval)
        // macOS turns the panel off about 5 seconds later.
        clock.now += 5
        reader.inputs.builtinAsleep = true
        let before = (levels: first.reads, sets: first.sets.count, angles: lid.reads)
        for _ in 0..<300 {
            clock.now += 2
            controller.update(lidClosed: true, holding: true, enabled: true, fade: true, now: clock.now)
        }
        XCTAssertEqual(first.reads, before.levels)
        XCTAssertEqual(first.sets.count, before.sets)
        XCTAssertEqual(lid.reads, before.angles)
        XCTAssertEqual(sleeper.requests, 0)
        // The lid opens, and the panel is not on yet.
        lid.degrees = 20
        watcher.onChange?(.lid(closed: false))
        XCTAssertNotNil(lid.onPush)
        tick(40, after: 0.5)
        XCTAssertEqual(first.sets.count, before.sets)
        XCTAssertEqual(panel.level, 0)
        reader.inputs.builtinAsleep = false
        tick(60, after: 0.5)
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertEqual(first.sets.count, before.sets + 1, "Once")
        XCTAssertNil(saved)
        move(from: 60, to: 110, over: 0.5)
        XCTAssertEqual(first.sets.count, before.sets + 1)
    }

    /// A sample is collected away from the main thread and applied later.
    /// One collected just before the lid switch says the lid is open.
    func testASampleFromBeforeTheLidSwitchDoesNotPutTheBrightnessBackUnderTheShutLid() {
        let watcher = Watcher()
        let controller = fading(watcher: watcher)
        tick(60, after: 0.5)
        move(from: 60, to: 0, over: 0.5)
        watcher.onChange?(.lid(closed: true))
        let sets = first.sets.count
        controller.update(lidClosed: false, holding: true, enabled: true, fade: true, now: clock.now - 0.05)
        XCTAssertEqual(first.sets.count, sets, "The switch decides about the lid")
        XCTAssertEqual(panel.level, 0)
        XCTAssertNotNil(saved)
        XCTAssertNil(lid.onPush, "The sensor stays closed")
        clock.now += 0.2
        controller.update(lidClosed: true, holding: true, enabled: true, fade: true, now: clock.now)
        XCTAssertEqual(first.sets.count, sets)
    }

    /// The lid opens next to an external display, and a sample from before
    /// the switch says it is closed.
    func testASampleFromBeforeTheLidSwitchDoesNotDimTheOpenLidNextToAnExternalDisplay() {
        reader.inputs.externalDisplay = true
        let watcher = Watcher()
        let method = Method("first", panel: panel)
        let controller = controller([method], watcher: watcher)
        controller.start(onChange: {})
        controller.update(lidClosed: false, holding: true, enabled: true, now: clock.now)
        clock.now += 1
        watcher.onChange?(.lid(closed: false))
        controller.update(lidClosed: true, holding: true, enabled: true, now: clock.now - 0.05)
        XCTAssertEqual(method.sets, [])
        XCTAssertEqual(panel.level, 0.6)
        XCTAssertNil(saved)
        clock.now += 2
        controller.update(lidClosed: false, holding: true, enabled: true, now: clock.now)
        XCTAssertEqual(method.sets, [])
    }

    func testAHoldThatEndsUnderTheShutLidGivesTheBrightnessBackWhenTheLidOpens() {
        let watcher = Watcher()
        let controller = fading(watcher: watcher)
        tick(60, after: 0.5)
        move(from: 60, to: 0, over: 0.5)
        watcher.onChange?(.lid(closed: true))
        reader.inputs.externalDisplay = true
        controller.update(lidClosed: true, holding: false, enabled: true, fade: true, now: clock.now + 10)
        XCTAssertNil(lid.onPush)
        XCTAssertEqual(panel.level, 0, "At the desk it stays dark until the lid opens")
        lid.degrees = 100
        watcher.onChange?(.lid(closed: false))
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertNil(saved)
        XCTAssertNil(lid.onPush, "No hold and no fade: the sensor is closed again")
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
        tick(nil, after: 0.3)
        XCTAssertLessThan(panel.level, 0.3, "An answer can be late")
        tick(nil, after: 0.3)
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertNil(saved)
    }

    func testWithTheSwitchOnEveryFadeLeavesATrace() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("caffeinagent-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = DisplayController(
            reader: reader, sleeper: sleeper, dimmer: BuiltinDimmer(methods: [Method("first", panel: panel)], defaults: defaults),
            lid: lid, ticker: ticker, trace: DisplayTraceRecorder(defaults: defaults, directory: directory), clock: { [clock] in clock.now }
        )
        kept = controller
        controller.update(lidClosed: false, holding: true, enabled: true, fade: true, now: clock.now)
        tick(60, after: 0.5)
        move(from: 60, to: 20, over: 0.5)
        for _ in 0..<300 { tick(20) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path), "Off unless the switch is on")

        defaults.set(true, forKey: DisplayTrace.defaultsKey)
        move(from: 20, to: 10, over: 0.25)
        for _ in 0..<300 { tick(10) }
        XCTAssertEqual(ticker.interval, LidPoll.slow.interval)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(names.count, 1, "Written when the lid is steady")
        let rows = try String(contentsOf: directory.appendingPathComponent(names[0]), encoding: .utf8).split(separator: "\n").map { $0.split(separator: "\t") }
        XCTAssertEqual(rows[0].joined(separator: "\t"), DisplayTrace.header)
        XCTAssertGreaterThan(rows.count, 100)
        XCTAssertEqual(rows[1][1], "19", "What the sensor gave")
        XCTAssertTrue(rows.dropFirst().contains { $0[4] != "-" }, "What was set")
        XCTAssertTrue(rows.dropFirst().allSatisfy { $0[6] == "0" }, "Nobody else set the brightness")
        XCTAssertEqual(rows.last?[2], "10.000")

        // Quit in the middle of a fade: what there is, is written.
        move(from: 10, to: 30, over: 0.25)
        controller.stop()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
    }

    // MARK: Replays

    /// The lid closes while an agent works: the fade at 30 readings a
    /// second, the lid switch, then 10 minutes of samples every 2 seconds.
    /// `panelSleeps` is what macOS does about 5 seconds after the switch.
    private func replayLidClose(panelSleeps: Bool) -> (fadeWrites: Int, writes: Int, sleeps: Int, readsUnderTheLid: Int) {
        let watcher = Watcher()
        let controller = fading(watcher: watcher)
        tick(110, after: 0.5)
        let frames = Int(0.6 / LidPoll.fast.interval)
        for frame in 1...frames { tick((110 - 110 * Double(frame) / Double(frames)).rounded(), after: LidPoll.fast.interval) }
        let fadeWrites = first.sets.count
        clock.now += 0.033
        watcher.onChange?(.lid(closed: true))
        let reads = first.reads
        for _ in 0..<300 {
            clock.now += 2
            if panelSleeps, clock.now.timeIntervalSince(start) > 6 { reader.inputs.builtinAsleep = true }
            controller.update(lidClosed: true, holding: true, enabled: true, fade: true, now: clock.now)
        }
        return (fadeWrites, first.sets.count, sleeper.requests, first.reads - reads)
    }

    /// Before: 27 writes at 120 a second, 2 requests for display sleep by
    /// the lid switch, and the brightness read twice a second under the lid.
    func testReplayLidCloseWithAnAgentAtWork() {
        let counts = replayLidClose(panelSleeps: true)
        XCTAssertEqual(counts.fadeWrites, 8)
        XCTAssertEqual(counts.writes, 8, "None under the lid")
        XCTAssertEqual(counts.sleeps, 0)
        XCTAssertEqual(counts.readsUnderTheLid, 0, "macOS turns the panel off within the 15 seconds")
    }

    /// Before: 102 requests for display sleep in 10 minutes.
    func testReplayLidCloseOnAPanelThatStaysLit() {
        let counts = replayLidClose(panelSleeps: false)
        XCTAssertEqual(counts.writes, 8)
        XCTAssertEqual(counts.sleeps, 2)
    }

    // MARK: Without the fade: at once, not at the next sample

    func testTheLidThatClosesIsActedOnWhenTheSwitchSaysSo() {
        let watcher = Watcher()
        var samples = 0
        let controller = controller([Method("first", panel: panel)], watcher: watcher)
        controller.start { samples += 1 }
        controller.update(lidClosed: false, holding: true, enabled: true, now: at(0))
        watcher.onChange?(.lid(closed: true))
        XCTAssertEqual(sleeper.requests, 0, "No display sleep at the lid switch")
        XCTAssertEqual(samples, 1, "One is asked for, for the rest of the app")
        clock.now += 15
        controller.update(lidClosed: true, holding: true, enabled: true, now: clock.now)
        XCTAssertEqual(sleeper.requests, 1, "The panel still reads on: the late request")
        watcher.onChange?(.lid(closed: false))
        XCTAssertEqual(sleeper.wakes, 1)
    }

    func testAChangeOfTheDisplaysPutsOffDisplaySleepFor15Seconds() {
        let watcher = Watcher()
        let controller = controller([Method("first", panel: panel)], watcher: watcher)
        controller.start(onChange: {})
        watcher.onChange?(.lid(closed: true))
        clock.now += 14
        watcher.onChange?(.displaysBegin)
        watcher.onChange?(.displaysDone)
        clock.now += DisplayController.settleTime
        delay.fire()
        XCTAssertEqual(sleeper.requests, 0, "Never right after a change of the displays")
        controller.update(lidClosed: true, holding: true, enabled: true, now: clock.now + 14)
        XCTAssertEqual(sleeper.requests, 0)
        controller.update(lidClosed: true, holding: true, enabled: true, now: clock.now + 15)
        XCTAssertEqual(sleeper.requests, 1)
    }

    /// Two displays are plugged in under the shut lid. While macOS sets
    /// them up, nothing is read or set: no brightness, no display sleep.
    func testAChangeOfTheDisplaysMakesNoCallInItsCallbackAndOneUpdateWhenTheySettled() {
        let watcher = Watcher()
        let method = Method("first", panel: panel)
        var samples = 0
        let controller = controller([method], watcher: watcher)
        controller.start { samples += 1 }
        controller.update(lidClosed: true, holding: true, enabled: true, now: clock.now)
        watcher.onChange?(.lid(closed: true))
        clock.now += 60
        controller.update(lidClosed: true, holding: true, enabled: true, now: clock.now)
        XCTAssertEqual(sleeper.requests, 1, "The built-in display still read on")
        samples = 0
        let before = (reader: reader.reads, levels: method.reads, sets: method.sets.count, sleeps: sleeper.requests)

        reader.inputs.externalDisplay = true
        reader.inputs.builtinOnline = false
        for change in [DisplayChange.displaysBegin, .displaysBegin, .displaysDone, .displaysDone] {
            watcher.onChange?(change)
            XCTAssertEqual(delay.seconds, change == .displaysBegin ? DisplayController.settleLimit : DisplayController.settleTime)
        }
        // A sample of the engine and the lid switch in that time wait too.
        controller.update(lidClosed: true, holding: true, enabled: true, now: clock.now + 1)
        watcher.onChange?(.lid(closed: true))
        controller.update(holding: false, now: clock.now + 1)
        controller.update(holding: true, now: clock.now + 1)
        XCTAssertEqual(reader.reads, before.reader)
        XCTAssertEqual(method.reads, before.levels)
        XCTAssertEqual(method.sets.count, before.sets)
        XCTAssertEqual(sleeper.requests, before.sleeps)
        XCTAssertEqual(samples, 1, "Only the sample of the lid")

        clock.now += DisplayController.settleTime
        delay.fire()
        XCTAssertEqual(reader.reads, before.reader + 1, "One update")
        XCTAssertEqual(samples, 2)
        XCTAssertNil(delay.seconds)
        XCTAssertEqual(sleeper.requests, before.sleeps, "Next to an external display nothing sleeps")
    }

    /// The displays are unplugged under the shut lid: no display sleep in
    /// the callback, and none for 15 seconds after they settled.
    func testDisplaysThatAreUnpluggedUnderTheShutLidAreNotPutToSleepAtOnce() {
        reader.inputs.externalDisplay = true
        let watcher = Watcher()
        let controller = controller([Method("first", panel: panel)], watcher: watcher)
        controller.start(onChange: {})
        controller.update(lidClosed: true, holding: true, enabled: true, now: clock.now)
        clock.now += 600
        reader.inputs.externalDisplay = false
        watcher.onChange?(.displaysBegin)
        watcher.onChange?(.displaysDone)
        XCTAssertEqual(sleeper.requests, 0)
        clock.now += DisplayController.settleTime
        delay.fire()
        XCTAssertEqual(sleeper.requests, 0)
        controller.update(lidClosed: true, holding: true, enabled: true, now: clock.now + 15)
        XCTAssertEqual(sleeper.requests, 1)
    }

    func testTheLidThatOpensGetsItsBrightnessBackWhenTheSwitchSaysSo() {
        reader.inputs.externalDisplay = true
        let watcher = Watcher()
        let controller = controller([Method("first", panel: panel)], watcher: watcher)
        controller.start(onChange: {})
        controller.update(lidClosed: false, holding: true, enabled: true, now: at(0))
        watcher.onChange?(.lid(closed: true))
        XCTAssertEqual(panel.level, 0.6, "No dim in the handler of the lid switch")
        // macOS changes the displays for the closed lid.
        watcher.onChange?(.displaysBegin)
        watcher.onChange?(.displaysDone)
        delay.fire()
        XCTAssertEqual(panel.level, 0, "Once they settled")
        watcher.onChange?(.lid(closed: false))
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
        XCTAssertNil(saved)
        // The list of displays changed: the lid is as it was.
        watcher.onChange?(.displaysBegin)
        watcher.onChange?(.displaysDone)
        delay.fire()
        XCTAssertEqual(panel.level, 0.6, accuracy: 0.001)
    }
}
