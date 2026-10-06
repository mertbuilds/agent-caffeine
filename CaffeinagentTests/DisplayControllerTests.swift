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

        func sleepDisplays() -> Bool {
            requests += 1
            return true
        }
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
        var onChange: (() -> Void)?
        var stopped = false

        func start(onChange: @escaping () -> Void) { self.onChange = onChange }
        func stop() { stopped = true }
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

    private func controller(_ methods: [Method], watcher: Watcher? = nil) -> DisplayController {
        DisplayController(reader: reader, sleeper: sleeper, dimmer: BuiltinDimmer(methods: methods, defaults: defaults), watcher: watcher)
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
}
