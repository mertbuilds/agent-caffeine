import XCTest

final class PauseTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func paused(_ choice: PauseChoice, at now: Date) -> Pause {
        var pause = Pause()
        pause.start(choice, now: now, calendar: calendar)
        return pause
    }

    // MARK: The end of a pause

    func testThirtyMinutesAndOneHour() {
        XCTAssertEqual(Pause.deadline(for: .thirtyMinutes, now: date(6, 15), calendar: calendar), date(6, 15, 30))
        XCTAssertEqual(Pause.deadline(for: .oneHour, now: date(6, 23, 30), calendar: calendar), date(7, 0, 30))
    }

    func testUntilTomorrowIsSixInTheMorning() {
        let cases: [(now: Date, until: Date)] = [
            (date(6, 15, 30), date(7, 6)),
            (date(6, 23, 59), date(7, 6)),
            // After midnight the next morning is today's.
            (date(7, 0, 30), date(7, 6)),
            (date(7, 2), date(7, 6)),
            // Less than 4 hours to the morning: 8 hours from now.
            (date(7, 2, 1), date(7, 10, 1)),
            (date(7, 5, 59), date(7, 13, 59)),
            // At 06:00 the next morning is a day away.
            (date(7, 6), date(8, 6)),
            (date(7, 6, 1), date(8, 6)),
        ]
        for c in cases {
            XCTAssertEqual(Pause.deadline(for: .untilTomorrow, now: c.now, calendar: calendar), c.until, "\(c.now)")
        }
    }

    func testNoChoiceIsLongerThanTheLongestPause() {
        // The night the clocks go back in Berlin has 25 hours.
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = berlin.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 6, minute: 0, second: 1))!
        let until = Pause.deadline(for: .untilTomorrow, now: now, calendar: berlin)
        XCTAssertEqual(berlin.dateComponents([.day, .hour], from: until), DateComponents(day: 25, hour: 6))
        XCTAssertLessThanOrEqual(until.timeIntervalSince(now), Pause.longest)
        var pause = Pause()
        pause.start(.untilTomorrow, now: now, calendar: berlin)
        XCTAssertTrue(pause.isPaused(now: now))
    }

    // MARK: Start, resume, end

    func testAPauseEndsAtItsTime() {
        var pause = paused(.thirtyMinutes, at: date(6, 15))
        XCTAssertEqual(pause.until, date(6, 15, 30))
        XCTAssertTrue(pause.isPaused(now: date(6, 15)))
        XCTAssertTrue(pause.isPaused(now: date(6, 15, 29)))
        XCTAssertFalse(pause.isPaused(now: date(6, 15, 30)), "Over at the minute it names")
        pause.settle(now: date(6, 15, 29))
        XCTAssertEqual(pause.until, date(6, 15, 30))
        pause.settle(now: date(6, 15, 30))
        XCTAssertNil(pause.until)
    }

    func testResumeEndsAPause() {
        var pause = paused(.untilTomorrow, at: date(6, 15))
        pause.resume()
        XCTAssertNil(pause.until)
        XCTAssertFalse(pause.isPaused(now: date(6, 15)))
        XCTAssertEqual(pause, Pause())
    }

    func testANewPauseReplacesTheOldOne() {
        var pause = paused(.untilTomorrow, at: date(6, 15))
        pause.start(.thirtyMinutes, now: date(6, 16), calendar: calendar)
        XCTAssertEqual(pause.until, date(6, 16, 30))
    }

    /// The Mac slept, or the app did not run: the time counts all the same.
    func testAPauseThatEndedWhileTheMacSleptIsOver() {
        var pause = paused(.oneHour, at: date(6, 15))
        pause.settle(now: date(7, 9))
        XCTAssertNil(pause.until)
    }

    func testRestoreFromTheSavedDate() {
        XCTAssertEqual(Pause(stored: date(6, 16), now: date(6, 15, 30)).until, date(6, 16))
        XCTAssertNil(Pause(stored: date(6, 16), now: date(6, 16)).until)
        XCTAssertNil(Pause(stored: date(6, 16), now: date(9, 12)).until, "Saved before a long time off")
        XCTAssertNil(Pause(stored: nil, now: date(6, 15)).until)
    }

    func testTheClockMovesForward() {
        var pause = paused(.oneHour, at: date(6, 15))
        pause.settle(now: date(6, 15, 59))
        XCTAssertNotNil(pause.until)
        pause.settle(now: date(6, 18))
        XCTAssertNil(pause.until)
    }

    /// The pause still ends when the clock shows its time. A clock that
    /// went back by more than the longest pause ends it.
    func testTheClockMovesBack() {
        var pause = paused(.oneHour, at: date(6, 15))
        pause.settle(now: date(6, 12))
        XCTAssertEqual(pause.until, date(6, 16))
        XCTAssertTrue(pause.isPaused(now: date(6, 12)))
        pause.settle(now: date(5, 14))
        XCTAssertNil(pause.until)
        XCTAssertNil(Pause(stored: date(6, 16), now: date(5, 14)).until)
    }

    // MARK: The switch

    func testTheSwitchEndsAPauseBothWays() {
        let now = date(6, 15)
        var state = PauseSwitch(enabled: true, pause: paused(.oneHour, at: now))
        state.set(enabled: false)
        XCTAssertEqual(state, PauseSwitch(enabled: false, pause: Pause()))
        state = PauseSwitch(enabled: true, pause: paused(.oneHour, at: now))
        state.set(enabled: true)
        XCTAssertEqual(state, PauseSwitch(enabled: true, pause: Pause()))
    }

    func testTheShortcutResumesAPauseAndElseTurnsTheSwitchOver() {
        let now = date(6, 15)
        var state = PauseSwitch(enabled: true, pause: paused(.oneHour, at: now))
        state.toggle(now: now)
        XCTAssertEqual(state, PauseSwitch(enabled: true, pause: Pause()), "A pause ends, the switch stays on")
        state.toggle(now: now)
        XCTAssertEqual(state, PauseSwitch(enabled: false, pause: Pause()))
        state.toggle(now: now)
        XCTAssertEqual(state, PauseSwitch(enabled: true, pause: Pause()))
        // A pause whose time is over counts as no pause.
        state = PauseSwitch(enabled: true, pause: paused(.oneHour, at: now))
        state.toggle(now: date(6, 17))
        XCTAssertEqual(state, PauseSwitch(enabled: false, pause: Pause()))
    }
}
