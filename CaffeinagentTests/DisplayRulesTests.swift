import XCTest

final class DisplayRulesTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_791_200_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// Lid closed, holding, the built-in display on at half brightness.
    private func closed(external: Bool = false, online: Bool = true, asleep: Bool = false, brightness: Float? = 0.5, idle: TimeInterval? = 600) -> DisplayInputs {
        DisplayInputs(lidClosed: true, holding: true, externalDisplay: external, builtinOnline: online, builtinAsleep: asleep, brightness: brightness, idle: idle)
    }

    private func kinds(_ actions: [DisplayAction]) -> [String] {
        actions.map {
            switch $0 {
            case .sleepDisplays: return "sleep"
            case .dimBuiltin: return "dim"
            case .restoreBuiltin: return "restore"
            }
        }
    }

    /// Runs the steps one after the other and gives what each one asked for.
    private func run(_ steps: [(seconds: TimeInterval, inputs: DisplayInputs)], enabled: Bool = true, memory: DisplayMemory = DisplayMemory()) -> ([[String]], DisplayMemory) {
        var memory = memory
        var all: [[String]] = []
        for step in steps {
            let (actions, next) = DisplayRules.decide(step.inputs, enabled: enabled, memory: memory, now: at(step.seconds))
            memory = next
            all.append(kinds(actions))
        }
        return (all, memory)
    }

    // MARK: Nothing to do

    func testNothingHappensWithTheLidOpen() {
        var inputs = closed()
        inputs.lidClosed = false
        XCTAssertEqual(run([(0, inputs), (10, inputs)]).0, [[], []])
    }

    func testNothingHappensWhenAgentCaffeineDoesNotHold() {
        var inputs = closed()
        inputs.holding = false
        XCTAssertEqual(run([(0, inputs), (10, inputs)]).0, [[], []])
        inputs.externalDisplay = true
        XCTAssertEqual(run([(0, inputs)]).0, [[]])
    }

    func testNothingHappensWithTheSettingOff() {
        XCTAssertEqual(run([(0, closed()), (10, closed(external: true))], enabled: false).0, [[], []])
    }

    func testADisplayThatSleepsIsLeftAlone() {
        XCTAssertEqual(run([(0, closed(asleep: true)), (10, closed(asleep: true)), (20, closed(external: true, asleep: true))]).0, [[], [], []])
    }

    // MARK: No external display

    func testTheDisplaysSleepAtOnceWhenTheLidCloses() {
        // The user typed a second before the lid closed. That is no use from afar.
        let (actions, memory) = run([(0, closed(idle: 1))])
        XCTAssertEqual(actions, [["sleep"]])
        XCTAssertEqual(memory.lidClosedAt, at(0))
    }

    func testTheRequestIsNotRepeatedWithinFiveSeconds() {
        let steps = [0, 2, 4, 4.9].map { (TimeInterval($0), closed()) }
        XCTAssertEqual(run(steps).0, [["sleep"], [], [], []])
    }

    /// Belt and braces: display sleep that does not hold also dims.
    func testADisplayThatStaysOnIsAskedAgainAndDimmed() {
        let (actions, memory) = run([(0, closed()), (2, closed()), (5, closed()), (7, closed())])
        XCTAssertEqual(actions, [["sleep"], [], ["sleep", "dim"], []])
        XCTAssertEqual(memory.sleepRequests, 2)
    }

    func testADisplayThatWakesUnderTheLidSleepsAgain() {
        let story: [(TimeInterval, DisplayInputs)] = [
            (0, closed()), (2, closed(asleep: true)), (600, closed(asleep: true)),
            // The charger was plugged in: the display is on with no key pressed.
            (602, closed(idle: 602)), (604, closed(asleep: true)),
        ]
        let (actions, memory) = run(story)
        XCTAssertEqual(actions, [["sleep"], [], [], ["sleep"], []])
        XCTAssertEqual(memory.sleepRequests, 0, "It held, so the next wake starts with sleep alone")
    }

    func testOnceDarkTheDisplayIsNotDimmedAgain() {
        var memory = DisplayMemory()
        memory.dimmed = true
        let dark = closed(brightness: 0)
        let (actions, _) = run([(0, dark), (5, dark), (10, dark)], memory: memory)
        XCTAssertEqual(actions, [["sleep"], ["sleep"], ["sleep"]], "Still asked to sleep, and not dimmed twice")
    }

    func testABrightnessThatCameUpAgainIsDimmedAgain() {
        var memory = DisplayMemory()
        memory.dimmed = true
        let (actions, _) = run([(0, closed(brightness: 0)), (5, closed(brightness: 0.4))], memory: memory)
        XCTAssertEqual(actions, [["sleep"], ["sleep", "dim"]])
    }

    func testWithoutABrightnessToReadTheDisplayIsDimmedOnce() {
        let unknown = closed(brightness: nil)
        var (actions, memory) = run([(0, unknown), (5, unknown)])
        XCTAssertEqual(actions, [["sleep"], ["sleep", "dim"]])
        memory.dimmed = true
        XCTAssertEqual(run([(10, unknown), (15, unknown)], memory: memory).0, [["sleep"], ["sleep"]])
    }

    /// Screen sharing with the lid closed: display sleep would lock the
    /// user out every few seconds.
    func testSomeoneWhoUsesTheMacFromAfarIsNotPutToSleep() {
        let story: [(TimeInterval, DisplayInputs)] = [
            (0, closed(asleep: true)),
            // A key was pressed 2 seconds ago, long after the lid closed.
            (100, closed(idle: 2)), (102, closed(idle: 1)), (106, closed(brightness: 0, idle: 1)),
            // A minute with no key: the display may sleep.
            (200, closed(brightness: 0, idle: 61)),
        ]
        XCTAssertEqual(run(story).0, [[], ["dim"], [], [], ["sleep"]])
    }

    func testAClockThatWentBackDoesNotStopTheRequests() {
        XCTAssertEqual(run([(100, closed()), (10, closed())]).0, [["sleep"], ["sleep", "dim"]])
    }

    // MARK: With an external display

    func testOnlyTheBuiltInDisplayIsDimmedNextToAnExternalDisplay() {
        let story = [0, 2, 5, 10].map { (TimeInterval($0), closed(external: true)) }
        let (actions, _) = run(story)
        XCTAssertEqual(actions, [["dim"], [], ["dim"], ["dim"]])
        XCTAssertFalse(actions.joined().contains("sleep"), "Display sleep would take the display the user works on")
    }

    func testTheBuiltInDisplayThatIsOffTheListIsDimmedWhenItsBrightnessReadsLit() {
        XCTAssertEqual(run([(0, closed(external: true, online: false))]).0, [["dim"]])
        XCTAssertEqual(run([(0, closed(external: true, online: false, brightness: 0))]).0, [[]])
        XCTAssertEqual(run([(0, closed(external: true, online: false, brightness: nil))]).0, [[]])
    }

    func testDimmingStopsAfterThreeTriesThatDidNotWork() {
        var memory = DisplayMemory()
        var asked: [[String]] = []
        for seconds in stride(from: 0, through: 30, by: 5) {
            let (actions, next) = DisplayRules.decide(closed(external: true), enabled: true, memory: memory, now: at(TimeInterval(seconds)))
            memory = next
            // What the controller does when the dimmer says no.
            if actions.contains(where: { if case .dimBuiltin = $0 { return true } else { return false } }) { memory.dimFailures += 1 }
            asked.append(kinds(actions))
        }
        XCTAssertEqual(asked, [["dim"], ["dim"], ["dim"], [], [], [], []])
        // The lid was open in between: it is tried again.
        var open = closed(external: true)
        open.lidClosed = false
        memory = DisplayRules.decide(open, enabled: true, memory: memory, now: at(40)).1
        XCTAssertEqual(kinds(DisplayRules.decide(closed(external: true), enabled: true, memory: memory, now: at(41)).0), ["dim"])
    }

    // MARK: Putting the brightness back

    private var dimmed: DisplayMemory {
        var memory = DisplayMemory()
        memory.dimmed = true
        memory.lidClosedAt = at(0)
        return memory
    }

    func testTheBrightnessComesBackWhenTheLidOpens() {
        for external in [false, true] {
            var open = closed(external: external, brightness: 0)
            open.lidClosed = false
            let (actions, memory) = DisplayRules.decide(open, enabled: true, memory: dimmed, now: at(60))
            XCTAssertEqual(actions, [.restoreBuiltin(reason: "the lid is open")])
            XCTAssertNil(memory.lidClosedAt)
        }
    }

    func testTheBrightnessComesBackWhenTheSettingGoesOff() {
        let (actions, _) = DisplayRules.decide(closed(external: true, brightness: 0), enabled: false, memory: dimmed, now: at(60))
        XCTAssertEqual(actions, [.restoreBuiltin(reason: "the setting is off")])
    }

    /// The Mac then sleeps, and wakes with its own brightness.
    func testTheBrightnessComesBackWhenTheHoldEndsWithoutAnExternalDisplay() {
        var released = closed(brightness: 0)
        released.holding = false
        XCTAssertEqual(kinds(DisplayRules.decide(released, enabled: true, memory: dimmed, now: at(60)).0), ["restore"])
        // At the desk the Mac stays awake, so the display stays dark.
        released.externalDisplay = true
        XCTAssertEqual(DisplayRules.decide(released, enabled: true, memory: dimmed, now: at(60)).0, [])
    }

    func testNothingIsPutBackThatWasNotDimmed() {
        var open = closed()
        open.lidClosed = false
        XCTAssertEqual(DisplayRules.decide(open, enabled: true, memory: DisplayMemory(), now: at(0)).0, [])
    }

    func testEveryActionSaysWhy() {
        let (actions, _) = DisplayRules.decide(closed(), enabled: true, memory: DisplayMemory(), now: at(0))
        XCTAssertEqual(actions, [.sleepDisplays(reason: "the lid is closed and the built-in display is on")])
        for action in actions + [.dimBuiltin(reason: "x"), .restoreBuiltin(reason: "y")] {
            XCTAssertFalse(action.reason.isEmpty)
        }
    }
}
