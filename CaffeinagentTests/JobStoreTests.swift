import XCTest

/// The access to the disk and the crontab as the app uses it, against a
/// folder and a command that exist only in the test. No test reads the
/// crontab, the launchd agents or the Hermes files of the person who runs it.
final class JobStoreTests: XCTestCase {
    private var home: URL!
    private static let patience: TimeInterval = 10
    private static let secrets = ["secret", "hunter2", "password", "sk-live", "acme", "clients", "--key"]

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("caffeinagent-jobs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/LaunchAgents"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: home)
    }

    /// A command that stands in for `/usr/bin/crontab`.
    private func command(_ body: String) throws -> URL {
        let url = home.appendingPathComponent("crontab-\(UUID().uuidString).sh")
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private func plist(label: String, hour: Int) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: [
            "Label": label, "StartCalendarInterval": ["Hour": hour, "Minute": 15],
            "ProgramArguments": ["/Users/someone/clients/acme-secret/run.sh", "--password", "hunter2secret"],
        ] as [String: Any], format: .xml, options: 0)
    }

    // MARK: Files

    func testAFolderGivesItsNamesAndAMissingOneIsMissing() throws {
        let access = SystemJobSourceAccess()
        let folder = home.appendingPathComponent("Library/LaunchAgents")
        try plist(label: "com.example.a", hour: 9).write(to: folder.appendingPathComponent("a.plist"))
        guard case .found(let names) = access.fileNames(in: folder) else { return XCTFail("The folder is there") }
        XCTAssertEqual(names, ["a.plist"])
        guard case .missing = access.fileNames(in: home.appendingPathComponent("nothing")) else { return XCTFail("No such folder") }
        guard case .failed = access.fileNames(in: folder.appendingPathComponent("a.plist")) else { return XCTFail("A file is no folder") }
    }

    func testAFileGivesItsDataAndALargeOneIsNotRead() throws {
        let access = SystemJobSourceAccess()
        let file = home.appendingPathComponent("jobs.json")
        try Data("{}".utf8).write(to: file)
        guard case .found(let data) = access.data(at: file) else { return XCTFail("The file is there") }
        XCTAssertEqual(data, Data("{}".utf8))
        guard case .missing = access.data(at: home.appendingPathComponent("none.json")) else { return XCTFail("No such file") }
        guard case .failed = access.data(at: home) else { return XCTFail("A folder is no file") }
        try Data(count: SystemJobSourceAccess.maxBytes + 1).write(to: file)
        guard case .failed(let reason) = access.data(at: file) else { return XCTFail("Too large") }
        XCTAssertEqual(reason, "The file is too large")
    }

    /// Dotfile managers keep a plist or the jobs file elsewhere and put a
    /// link in its place.
    func testALinkToAFileIsReadAndALinkToAnythingElseIsNot() throws {
        let access = SystemJobSourceAccess()
        let files = FileManager.default
        let real = home.appendingPathComponent("dotfiles-jobs.json")
        try Data(#"{"jobs": []}"#.utf8).write(to: real)
        let link = home.appendingPathComponent("jobs.json")
        try files.createSymbolicLink(at: link, withDestinationURL: real)
        guard case .found(let data) = access.data(at: link) else { return XCTFail("A link to a file is read") }
        XCTAssertEqual(data, Data(#"{"jobs": []}"#.utf8))

        let twice = home.appendingPathComponent("link-to-link.json")
        try files.createSymbolicLink(at: twice, withDestinationURL: link)
        guard case .found = access.data(at: twice) else { return XCTFail("A link to a link to a file is read") }

        let toFolder = home.appendingPathComponent("folder.json")
        try files.createSymbolicLink(at: toFolder, withDestinationURL: home.appendingPathComponent("Library"))
        guard case .failed(let folderReason) = access.data(at: toFolder) else { return XCTFail("A link to a folder is no file") }
        XCTAssertEqual(folderReason, "It is no file")

        // A pipe with no writer: the open must not wait for one.
        let pipe = home.appendingPathComponent("pipe")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        let toPipe = home.appendingPathComponent("pipe.json")
        try files.createSymbolicLink(at: toPipe, withDestinationURL: pipe)
        for url in [pipe, toPipe] {
            guard case .failed(let reason) = access.data(at: url) else { return XCTFail("A pipe is no file") }
            XCTAssertEqual(reason, "It is no file")
        }

        let toDevice = home.appendingPathComponent("zero.json")
        try files.createSymbolicLink(at: toDevice, withDestinationURL: URL(fileURLWithPath: "/dev/zero"))
        guard case .failed(let deviceReason) = access.data(at: toDevice) else { return XCTFail("A device is no file") }
        XCTAssertEqual(deviceReason, "It is no file")

        let large = home.appendingPathComponent("large.bin")
        try Data(count: SystemJobSourceAccess.maxBytes + 1).write(to: large)
        let toLarge = home.appendingPathComponent("large.json")
        try files.createSymbolicLink(at: toLarge, withDestinationURL: large)
        guard case .failed(let largeReason) = access.data(at: toLarge) else { return XCTFail("Too large behind a link too") }
        XCTAssertEqual(largeReason, "The file is too large")
        try Data(count: SystemJobSourceAccess.maxBytes).write(to: large)
        guard case .found(let most) = access.data(at: toLarge) else { return XCTFail("The limit itself is read") }
        XCTAssertEqual(most.count, SystemJobSourceAccess.maxBytes)

        let dangling = home.appendingPathComponent("dangling.json")
        try files.createSymbolicLink(at: dangling, withDestinationURL: home.appendingPathComponent("gone.json"))
        guard case .missing = access.data(at: dangling) else { return XCTFail("A link to nothing is no file that is there") }
    }

    /// A launchd agent behind a link is found like any other.
    func testALaunchdAgentBehindALinkIsFound() throws {
        let real = home.appendingPathComponent("dotfiles-agent.plist")
        try plist(label: "com.example.linked", hour: 9).write(to: real)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Library/LaunchAgents/com.example.linked.plist"), withDestinationURL: real)
        let reading = LaunchAgentsJobReader(home: home).read(SystemJobSourceAccess())
        XCTAssertEqual(reading.jobs.map(\.name), ["com.example.linked"])
        JobPrivacy.check(reading.jobs, neverHolds: Self.secrets)
    }

    // MARK: crontab

    func testWhatTheCommandPrintsIsTheCrontab() throws {
        let access = SystemJobSourceAccess(crontabCommand: try command("[ \"$1\" = \"-l\" ] || exit 9\necho '15 3 * * * /Users/someone/bin/backup.sh --key sk-live-abc'"))
        guard case .found(let text) = access.crontab() else { return XCTFail("The command printed a crontab") }
        XCTAssertEqual(CrontabJobReader.jobs(text).map(\.name), ["backup.sh"])
    }

    func testNoCrontabIsMissingAndAnotherFailureSaysNothingOfTheOutput() throws {
        let none = SystemJobSourceAccess(crontabCommand: try command("echo 'crontab: no crontab for someone' >&2\nexit 1"))
        guard case .missing = none.crontab() else { return XCTFail("No crontab is no failure") }
        let broken = SystemJobSourceAccess(crontabCommand: try command("echo 'hunter2secret'\necho 'sk-live-errsecret' >&2\nexit 2"))
        guard case .failed(let reason) = broken.crontab() else { return XCTFail("Code 2 is a failure") }
        XCTAssertEqual(reason, "crontab ended with code 2")
    }

    func testACommandThatHangsIsStoppedAndOneThatIsNotThereFails() throws {
        let slow = SystemJobSourceAccess(crontabCommand: try command("exec sleep 30"), timeout: 0.3)
        let started = Date()
        guard case .failed(let reason) = slow.crontab() else { return XCTFail("It gave no answer") }
        XCTAssertEqual(reason, "crontab gave no answer")
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        let absent = SystemJobSourceAccess(crontabCommand: home.appendingPathComponent("no-such-command"))
        guard case .failed(let why) = absent.crontab() else { return XCTFail("Nothing to start") }
        XCTAssertEqual(why, "crontab could not be started")
    }

    // MARK: The store

    func testOneReadingHasTheThreeSourcesAndNothingButTimesAndNames() throws {
        let access = FixtureJobAccess()
        access.add("Library/LaunchAgents/a.plist", try plist(label: "com.example.a", hour: 9))
        access.crontabResult = .found("0 4 * * * /Users/someone/clients/acme-secret/sync --key sk-live-abc")
        access.add(".hermes/cron/jobs.json", Data(#"{"jobs":[{"id":"j1","name":"Digest","prompt":"the secret plan","schedule":{"kind":"cron","expr":"0 7 * * *"}}]}"#.utf8))
        let readings = JobStore.read(access: access, home: FixtureJobAccess.home, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(readings.map(\.source), [.launchd, .crontab, .hermes])
        XCTAssertEqual(readings.map(\.status), [.ok, .ok, .ok])
        XCTAssertEqual(readings.flatMap(\.jobs).map(\.name), ["com.example.a", "sync", "Hermes job j1"])
        JobPrivacy.check(readings.flatMap(\.jobs), neverHolds: Self.secrets + ["plan", "someone", "Digest"])
        let line = JobStore.logLine(readings)
        XCTAssertEqual(line, "jobs: launchd 1, crontab 1, hermes 1")
    }

    func testTheLogLineOfASourceThatCannotBeReadHasNoReason() {
        let readings = [JobSourceReading(source: .launchd, jobs: []), JobSourceReading(source: .hermes, unreadable: "jobs.json is no JSON")]
        XCTAssertEqual(JobStore.logLine(readings), "jobs: launchd 0, hermes unreadable")
    }

    func testTheStoreReadsAtOnceAndAgainWhenTheFolderChanges() throws {
        let access = SystemJobSourceAccess(crontabCommand: try command("echo 'crontab: no crontab for someone' >&2\nexit 1"))
        let store = JobStore(access: access, home: home, timeZone: { TimeZone(identifier: "UTC")! })
        let first = expectation(description: "the first reading")
        let second = expectation(description: "the reading after the change")
        var seen: [[JobSourceReading]] = []
        store.start { readings in
            XCTAssertTrue(Thread.isMainThread)
            seen.append(readings)
            if seen.count == 1 { first.fulfill() }
            if seen.count == 2 { second.fulfill() }
        }
        wait(for: [first], timeout: Self.patience)
        XCTAssertEqual(seen[0].map(\.status), [.none, .none, .none])
        try plist(label: "com.example.new", hour: 3).write(to: home.appendingPathComponent("Library/LaunchAgents/new.plist"))
        wait(for: [second], timeout: Self.patience)
        XCTAssertEqual(seen[1][0].jobs.map(\.id), ["launchd:com.example.new"])
        store.stop()
    }
}
