import XCTest

final class JobSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = TestDefaults()
    }

    func testFreshInstallGivesDefaults() {
        let settings = JobSettingsStore.load(from: defaults)
        XCTAssertEqual(settings, JobSettings())
        XCTAssertNil(defaults.data(forKey: JobSettingsStore.key))
        XCTAssertFalse(settings.wakeForJobs, "Off until the user switches it on")
        XCTAssertTrue(settings.onPowerOnly)
        XCTAssertEqual(settings.leadTime, 60)
        XCTAssertEqual(settings.maxWakesPerDay, 12)
        XCTAssertEqual(settings.startGrace, 240)
        XCTAssertEqual(settings.holdCap, 1800)
        XCTAssertEqual(settings.jobSwitches, [:])
    }

    func testSaveAndLoad() {
        var settings = JobSettings()
        settings.wakeForJobs = true
        settings.onPowerOnly = false
        settings.leadTime = 90
        settings.maxWakesPerDay = 4
        settings.startGrace = 180
        settings.holdCap = 3600
        settings.set(true, for: "launchd:com.example.backup")
        settings.set(true, for: "crontab:0 3 * * *:backup.sh")
        JobSettingsStore.save(settings, to: defaults)
        XCTAssertEqual(JobSettingsStore.load(from: defaults), settings)
    }

    func testTheKeyIsNotTheKeyOfTheDetectionSettings() {
        XCTAssertNotEqual(JobSettingsStore.key, DetectionSettingsStore.key)
        var detection = DetectionSettings()
        detection.waitingHold = 60
        DetectionSettingsStore.save(detection, to: defaults)
        var jobs = JobSettings()
        jobs.wakeForJobs = true
        JobSettingsStore.save(jobs, to: defaults)
        XCTAssertEqual(DetectionSettingsStore.load(from: defaults), detection)
        XCTAssertEqual(JobSettingsStore.load(from: defaults), jobs)
    }

    func testAJobIsOffUntilItIsSwitchedOn() {
        var settings = JobSettings()
        XCTAssertFalse(settings.isOn("launchd:a"))
        settings.set(true, for: "launchd:a")
        XCTAssertTrue(settings.isOn("launchd:a"))
        XCTAssertFalse(settings.isOn("launchd:b"))
        let found = [
            ScheduledJob(id: "launchd:a", source: .launchd, name: "a", schedule: .calendar([JobTime.cron("0 9 * * *")])),
            ScheduledJob(id: "launchd:b", source: .launchd, name: "b", schedule: .calendar([JobTime.cron("0 9 * * *")]), enabled: true),
        ]
        XCTAssertEqual(settings.applied(to: found).map(\.enabled), [true, false], "Only the switch of the user counts")
        settings.set(false, for: "launchd:a")
        XCTAssertEqual(settings.jobSwitches, [:], "A job that is off has no entry")
        XCTAssertEqual(settings.applied(to: found).map(\.enabled), [false, false])
    }

    func testMissingKeysKeepTheirDefaults() {
        defaults.set(Data(#"{"wakeForJobs":true}"#.utf8), forKey: JobSettingsStore.key)
        var want = JobSettings()
        want.wakeForJobs = true
        XCTAssertEqual(JobSettingsStore.load(from: defaults), want)
        defaults.set(Data(#"{"jobSwitches":{"crontab:x":true,"crontab:y":false},"new":1}"#.utf8), forKey: JobSettingsStore.key)
        let loaded = JobSettingsStore.load(from: defaults)
        XCTAssertFalse(loaded.wakeForJobs)
        XCTAssertEqual(loaded.jobSwitches, ["crontab:x": true])
    }

    func testNumbersOutOfRangeAreNotTaken() throws {
        func decode(_ json: String) throws -> JobSettings {
            try JSONDecoder().decode(JobSettings.self, from: Data(json.utf8))
        }
        let low = try decode(#"{"leadTime":0,"maxWakesPerDay":0,"startGrace":-5,"holdCap":1}"#)
        XCTAssertEqual(low.leadTime, 30)
        XCTAssertEqual(low.maxWakesPerDay, 1)
        XCTAssertEqual(low.startGrace, 60)
        XCTAssertEqual(low.holdCap, 300)

        let high = try decode(#"{"leadTime":1e300,"maxWakesPerDay":1000,"startGrace":86400,"holdCap":1e12}"#)
        XCTAssertEqual(high.leadTime, 1800)
        XCTAssertEqual(high.maxWakesPerDay, 48, "The helper refuses more")
        XCTAssertEqual(high.startGrace, 1800)
        XCTAssertEqual(high.holdCap, 7200)
        XCTAssertLessThanOrEqual(high.holdCap, JobHold.capLimit)

        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        let odd = try decoder.decode(JobSettings.self, from: Data(#"{"leadTime":"nan","startGrace":"inf","holdCap":"-inf"}"#.utf8))
        XCTAssertEqual(odd, JobSettings())

        let fine = try decode(#"{"leadTime":30,"maxWakesPerDay":48,"startGrace":600,"holdCap":7200}"#)
        XCTAssertEqual(fine.leadTime, 30)
        XCTAssertEqual(fine.maxWakesPerDay, 48)
        XCTAssertEqual(fine.startGrace, 600)
        XCTAssertEqual(fine.holdCap, 7200)
    }

    func testUnreadableSettingsGiveDefaults() {
        defaults.set(Data("not json".utf8), forKey: JobSettingsStore.key)
        XCTAssertEqual(JobSettingsStore.load(from: defaults), JobSettings())
        defaults.set(Data(#"{"wakeForJobs":"yes"}"#.utf8), forKey: JobSettingsStore.key)
        XCTAssertEqual(JobSettingsStore.load(from: defaults), JobSettings())
        defaults.set(Data(#"{"jobSwitches":["a"]}"#.utf8), forKey: JobSettingsStore.key)
        XCTAssertEqual(JobSettingsStore.load(from: defaults), JobSettings(), "The feature is off, and so is every job")
    }
}
