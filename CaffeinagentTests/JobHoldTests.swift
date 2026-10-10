import XCTest

final class JobHoldTests: XCTestCase {
    /// The time of the job. The alarm is a minute before it.
    private static let fire = JobTime.date("2026-10-10 03:00")

    private func at(_ seconds: TimeInterval) -> Date { Self.fire.addingTimeInterval(seconds) }

    private func job(_ source: ScheduledJob.Source = .crontab, on: Bool = true) -> ScheduledJob {
        ScheduledJob(id: "\(source.rawValue):backup", source: source, name: "backup.sh", schedule: .cron(JobTime.cron("0 3 * * *")), enabled: on)
    }

    private func hold(_ source: ScheduledJob.Source = .crontab, settings: JobSettings = JobSettings(), file: StaticString = #filePath, line: UInt = #line) -> JobHold {
        guard let hold = JobHold.open(job: job(source), fireAt: Self.fire, settings: settings) else {
            XCTFail("No hold", file: file, line: line)
            return JobHold(id: "", jobID: "", source: source, name: "", start: 0, fireAt: 0, startGrace: 0, cap: 0)
        }
        return hold
    }

    func testItOpensAtTheTimeOfTheAlarm() {
        let hold = self.hold()
        XCTAssertEqual(hold.startedAt, at(-60))
        XCTAssertFalse(hold.isTimely(now: at(-61)))
        XCTAssertEqual(hold.state(now: at(-61)), .notOpen)
        XCTAssertTrue(hold.isTimely(now: at(-60)))
        XCTAssertEqual(hold.state(now: at(-60)), .waiting)
        XCTAssertTrue(hold.isTimely(now: at(0)))
        XCTAssertEqual(hold.id, "crontab:backup@\(Int(Self.fire.timeIntervalSince1970))")
        XCTAssertEqual(hold.jobID, "crontab:backup")
        XCTAssertEqual(hold.title, "backup.sh")
        XCTAssertEqual(hold.subject, "backup.sh")
    }

    func testOnlyAJobTheUserSwitchedOnHolds() {
        XCTAssertNil(JobHold.open(job: job(on: false), fireAt: Self.fire, settings: JobSettings()))
    }

    func testTheLeadTimeOfTheSettings() {
        var settings = JobSettings()
        settings.leadTime = 300
        XCTAssertEqual(hold(settings: settings).startedAt, at(-300))
    }

    func testItEndsAtTheStartGraceWhenTheJobNeverStarts() {
        var hold = self.hold()
        XCTAssertEqual(JobSettings().startGrace, 240)
        XCTAssertEqual(hold.endsAt, at(240))
        for seconds in stride(from: -60.0, to: 240, by: 20) {
            hold.observe(running: false, now: at(seconds))
            XCTAssertTrue(hold.isTimely(now: at(seconds)), "\(seconds)")
        }
        XCTAssertFalse(hold.isTimely(now: at(240)))
        XCTAssertEqual(hold.state(now: at(240)), .neverStarted)
        XCTAssertNil(hold.seenAt)
        XCTAssertNil(hold.endedAt)
    }

    func testItEndsWhenTheJobIsSeenToEnd() {
        var hold = self.hold()
        hold.observe(running: false, now: at(2))
        hold.observe(running: true, now: at(4))
        XCTAssertEqual(hold.state(now: at(4)), .running)
        XCTAssertEqual(hold.endsAt, at(-60 + 1800), "A job that runs holds up to the cap")
        hold.observe(running: true, now: at(600))
        XCTAssertTrue(hold.isTimely(now: at(600)), "Past the start grace, because it runs")
        hold.observe(running: false, now: at(620))
        XCTAssertFalse(hold.isTimely(now: at(620)))
        XCTAssertEqual(hold.state(now: at(620)), .ended)
        XCTAssertEqual(hold.endsAt, at(620))
        XCTAssertEqual(hold.seenAt, at(4).timeIntervalSince1970)

        hold.observe(running: true, now: at(640))
        XCTAssertFalse(hold.isTimely(now: at(640)), "A hold that is over stays over")
        XCTAssertEqual(hold.endsAt, at(620))
    }

    func testAJobThatStartsBeforeItsTimeCounts() {
        var hold = self.hold()
        hold.observe(running: true, now: at(-30))
        hold.observe(running: false, now: at(-10))
        XCTAssertEqual(hold.state(now: at(-10)), .ended)
        XCTAssertFalse(hold.isTimely(now: at(0)))
    }

    func testItEndsAtTheCap() {
        var hold = self.hold()
        XCTAssertEqual(JobSettings().holdCap, 1800)
        hold.observe(running: true, now: at(10))
        for seconds in stride(from: 10.0, to: 1740, by: 60) {
            hold.observe(running: true, now: at(seconds))
            XCTAssertTrue(hold.isTimely(now: at(seconds)), "\(seconds)")
        }
        XCTAssertFalse(hold.isTimely(now: at(1740)), "30 minutes after the alarm")
        XCTAssertEqual(hold.state(now: at(1740)), .cutAtCap)
        hold.observe(running: true, now: at(1800))
        XCTAssertEqual(hold.endsAt, at(1740), "It never makes itself longer")
        hold.observe(running: false, now: at(1900))
        XCTAssertNil(hold.endedAt, "Nothing is seen after the hold")
    }

    func testTheCapOfTheSettingsAndItsLimit() {
        var settings = JobSettings()
        settings.holdCap = 3600
        var long = self.hold(settings: settings)
        long.observe(running: true, now: at(0))
        XCTAssertEqual(long.endsAt, at(-60 + 3600))
        settings.holdCap = 100_000
        XCTAssertEqual(hold(settings: settings).cap, JobHold.capLimit)
        settings.holdCap = 120
        settings.startGrace = 240
        XCTAssertEqual(hold(settings: settings).endsAt, at(60), "The cap is before the start grace")
    }

    func testAJobSeenAfterTheStartGraceDoesNotOpenTheHoldAgain() {
        var hold = self.hold()
        hold.observe(running: true, now: at(300))
        XCTAssertNil(hold.seenAt)
        XCTAssertFalse(hold.isTimely(now: at(300)))
        XCTAssertEqual(hold.state(now: at(300)), .neverStarted)
    }

    func testAnAgentJobIsABridgeToTheDetectionEngine() {
        var hold = self.hold(.hermes)
        XCTAssertFalse(hold.isWatched)
        XCTAssertEqual(hold.endsAt, at(300), "Five minutes after its time")
        hold.observe(running: true, now: at(10))
        XCTAssertNil(hold.seenAt, "What the agent does is the business of the engine")
        XCTAssertEqual(hold.endsAt, at(300))
        XCTAssertTrue(hold.isTimely(now: at(299)))
        XCTAssertFalse(hold.isTimely(now: at(300)))
        XCTAssertEqual(hold.state(now: at(300)), .bridgeOver)
        XCTAssertTrue(self.hold(.launchd).isWatched)
        XCTAssertEqual(self.hold(.launchd).endsAt, at(240))
    }

    func testAHoldThatIsNoHold() {
        var broken = self.hold()
        broken.cap = 100_000
        XCTAssertFalse(broken.isTimely(now: at(0)), "Longer than any job holds")
        broken = self.hold()
        broken.cap = 0
        XCTAssertFalse(broken.isTimely(now: at(0)))
        broken = self.hold()
        broken.start = .nan
        XCTAssertFalse(broken.isTimely(now: at(0)))
        broken = self.hold()
        broken.fireAt = broken.start - 1
        XCTAssertFalse(broken.isTimely(now: at(0)), "The alarm is never after the job")
    }

    func testAClockThatWasSetBackClosesIt() {
        var hold = self.hold()
        hold.observe(running: true, now: at(10))
        XCTAssertFalse(hold.isTimely(now: at(-3600)))
        hold.observe(running: false, now: at(-3600))
        XCTAssertNil(hold.endedAt)
    }

    func testItIsSavedAndReadBack() throws {
        var hold = self.hold()
        hold.observe(running: true, now: at(5))
        let data = try JSONEncoder().encode(hold)
        XCTAssertEqual(try JSONDecoder().decode(JobHold.self, from: data), hold)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("schedule"), "A hold holds the name and times of one run")
    }
}
