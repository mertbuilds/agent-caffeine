import XCTest

final class LaunchAgentsJobReaderTests: XCTestCase {
    private let reader = LaunchAgentsJobReader(home: FixtureJobAccess.home)
    private var access: FixtureJobAccess!

    override func setUp() {
        access = FixtureJobAccess()
    }

    /// A plist as a tool or an app writes it, with what must never be kept.
    private func plist(_ keys: [String: Any], label: String? = "com.example.backup", format: PropertyListSerialization.PropertyListFormat = .xml) throws -> Data {
        var all: [String: Any] = [
            "ProgramArguments": ["/Users/someone/clients/acme-secret/run.sh", "--password", "hunter2secret"],
            "EnvironmentVariables": ["API_TOKEN": "sk-live-envsecret"],
            "StandardOutPath": "/tmp/private-log.txt",
            "WorkingDirectory": "/Users/someone/clients",
        ]
        all["Label"] = label
        all.merge(keys) { $1 }
        return try PropertyListSerialization.data(fromPropertyList: all, format: format, options: 0)
    }

    private func add(_ name: String, _ data: Data) {
        access.add("Library/LaunchAgents/\(name)", data)
    }

    func testAnXMLPlistAndABinaryPlist() throws {
        let xml = try plist(["StartCalendarInterval": ["Hour": 9, "Minute": 15]], label: "com.example.daily")
        let binary = try plist(["StartCalendarInterval": [["Hour": 3, "Minute": 0], ["Weekday": 7, "Hour": 18, "Minute": 30]]], label: "com.example.twice", format: .binary)
        XCTAssertTrue(xml.starts(with: Data("<?xml".utf8)))
        XCTAssertTrue(binary.starts(with: Data("bplist".utf8)))
        add("com.example.daily.plist", xml)
        add("com.example.twice.plist", binary)
        let reading = reader.read(access)
        XCTAssertEqual(reading.status, .ok)
        XCTAssertEqual(reading.jobs, [
            ScheduledJob(id: "launchd:com.example.daily", source: .launchd, name: "com.example.daily", schedule: .calendar([JobTime.cron("15 9 * * *")])),
            ScheduledJob(id: "launchd:com.example.twice", source: .launchd, name: "com.example.twice", schedule: .calendar([JobTime.cron("0 3 * * *"), JobTime.cron("30 18 * * 0")])),
        ])
        XCTAssertTrue(reading.jobs.allSatisfy { !$0.enabled }, "Nothing is adopted by itself")
        XCTAssertEqual(access.asked.first, "/Users/fixture/Library/LaunchAgents")
    }

    func testAJobHoldsOnlyItsLabelAndItsTimes() throws {
        add("a.plist", try plist(["StartCalendarInterval": ["Hour": 9, "Minute": 15]]))
        add("b.plist", try plist(["StartCalendarInterval": ["Hour": 1]], label: "com.example.binary", format: .binary))
        let jobs = reader.read(access).jobs
        XCTAssertEqual(jobs.count, 2)
        JobPrivacy.check(jobs, neverHolds: ["secret", "hunter2", "password", "sk-live", "someone", "acme", "clients", "run.sh", "/tmp", "private", "TOKEN", "--"])
    }

    func testWhatIsNotOffered() throws {
        let calendar: [String: Any] = ["Hour": 9, "Minute": 15]
        add("interval.plist", try plist(["StartInterval": 3600], label: "com.example.interval"))
        add("load.plist", try plist(["RunAtLoad": true], label: "com.example.load"))
        add("watch.plist", try plist(["WatchPaths": ["/tmp/x"]], label: "com.example.watch"))
        add("disabled.plist", try plist(["StartCalendarInterval": calendar, "Disabled": true], label: "com.example.disabled"))
        add("alive.plist", try plist(["StartCalendarInterval": calendar, "KeepAlive": true], label: "com.example.alive"))
        add("alive2.plist", try plist(["StartCalendarInterval": calendar, "KeepAlive": ["SuccessfulExit": false]], label: "com.example.alive2"))
        add("apple.plist", try plist(["StartCalendarInterval": calendar], label: "com.apple.something"))
        add("wrong.plist", try plist(["StartCalendarInterval": ["Hour": 25]], label: "com.example.wrong"))
        add("broken.plist", Data("<?xml not a plist".utf8))
        add("list.plist", try PropertyListSerialization.data(fromPropertyList: ["a", "b"], format: .xml, options: 0))
        add("notes.txt", try plist(["StartCalendarInterval": calendar], label: "com.example.text"))
        add(".hidden.plist", try plist(["StartCalendarInterval": calendar], label: "com.example.hidden"))
        access.fail("Library/LaunchAgents/locked.plist", "Permission denied")
        add("locked.plist", try plist(["StartCalendarInterval": calendar], label: "com.example.locked"))
        XCTAssertEqual(reader.read(access), JobSourceReading(source: .launchd, jobs: []))

        add("both.plist", try plist(["StartCalendarInterval": calendar, "StartInterval": 3600, "RunAtLoad": true, "KeepAlive": false, "Disabled": false], label: "com.example.both"))
        XCTAssertEqual(reader.read(access).jobs.map(\.id), ["launchd:com.example.both"], "The calendar of a job that also has an interval")
    }

    func testTheLabel() throws {
        let calendar: [String: Any] = ["Hour": 9, "Minute": 15]
        add("com.example.nolabel.plist", try plist(["StartCalendarInterval": calendar], label: nil))
        add("long.plist", try plist(["StartCalendarInterval": calendar], label: "com.example." + String(repeating: "x", count: 100)))
        add("lines.plist", try plist(["StartCalendarInterval": calendar], label: "com.example.two\nlines"))
        add("same1.plist", try plist(["StartCalendarInterval": calendar], label: "com.example.same"))
        add("same2.plist", try plist(["StartCalendarInterval": ["Hour": 1]], label: "com.example.same"))
        let jobs = reader.read(access).jobs
        XCTAssertEqual(jobs.map(\.name), [
            "com.example.nolabel", "com.example.two lines", "com.example." + String(repeating: "x", count: 48), "com.example.same",
        ], "By file name, and the first of two files with one label")
        XCTAssertEqual(jobs[2].id, "launchd:com.example." + String(repeating: "x", count: 100))
        XCTAssertTrue(jobs.allSatisfy { $0.name.count <= ScheduledJob.nameLimit })
    }

    func testTheStatusOfTheSource() throws {
        XCTAssertEqual(reader.read(access).status, JobSourceStatus.none, "No folder is no failure")
        access.fail("Library/LaunchAgents", "Permission denied")
        XCTAssertEqual(reader.read(access), JobSourceReading(source: .launchd, unreadable: "Permission denied"))
        XCTAssertEqual(reader.read(access).status, .unreadable("Permission denied"))
    }

    func testTheReasonIsOneShortLine() {
        XCTAssertEqual(JobSourceStatus.unreadable(reason: "one\ntwo"), .unreadable("one two"))
        XCTAssertEqual(JobSourceStatus.unreadable(reason: ""), .unreadable("It could not be read"))
        guard case .unreadable(let text) = JobSourceStatus.unreadable(reason: String(repeating: "a", count: 200)) else { return XCTFail() }
        XCTAssertEqual(text.count, JobSourceStatus.reasonLimit)
    }
}
