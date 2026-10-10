import XCTest

/// Times and clocks for the tests of scheduled jobs.
enum JobTime {
    static let losAngeles = "America/Los_Angeles"
    static let istanbul = "Europe/Istanbul"
    static let utc = "UTC"

    static func clock(_ zone: String = utc) -> JobClock {
        JobClock(timeZone: TimeZone(identifier: zone)!)
    }

    /// "2026-03-08 02:30" on the wall clock of the zone.
    static func date(_ text: String, _ zone: String = utc) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: zone)!
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    static func cron(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> CronExpression {
        guard let expression = CronExpression.parse(text) else {
            XCTFail("\(text) is no cron expression", file: file, line: line)
            return CronExpression(minutes: [], hours: [], days: [], months: [], weekdays: [], anyDay: true, anyWeekday: true)
        }
        return expression
    }
}

/// Files, folders and a crontab that exist only in a test.
final class FixtureJobAccess: JobSourceAccess {
    static let home = URL(fileURLWithPath: "/Users/fixture")

    var files: [String: Data] = [:]
    var failures: [String: String] = [:]
    var crontabResult: JobSourceRead<String> = .missing
    private(set) var asked: [String] = []

    func add(_ path: String, _ data: Data) {
        files[Self.home.appendingPathComponent(path).path] = data
    }

    func fail(_ path: String, _ reason: String) {
        failures[Self.home.appendingPathComponent(path).path] = reason
    }

    func fileNames(in folder: URL) -> JobSourceRead<[String]> {
        asked.append(folder.path)
        if let reason = failures[folder.path] { return .failed(reason) }
        let prefix = folder.path + "/"
        let names = files.keys.filter { $0.hasPrefix(prefix) && !$0.dropFirst(prefix.count).contains("/") }.map { String($0.dropFirst(prefix.count)) }
        return names.isEmpty ? .missing : .found(names)
    }

    func data(at file: URL) -> JobSourceRead<Data> {
        asked.append(file.path)
        if let reason = failures[file.path] { return .failed(reason) }
        return files[file.path].map { .found($0) } ?? .missing
    }

    func crontab() -> JobSourceRead<String> { crontabResult }
}

enum JobPrivacy {
    /// What a job holds, by the names of its fields.
    static let fields = ["id", "source", "name", "schedule", "enabled", "noSwitch"]

    /// Fails when a job has a field more, or when any text of a job holds
    /// one of the words.
    static func check(_ jobs: [ScheduledJob], neverHolds words: [String], file: StaticString = #filePath, line: UInt = #line) {
        for job in jobs {
            XCTAssertEqual(Mirror(reflecting: job).children.map { $0.label ?? "" }, fields, file: file, line: line)
            var all = ""
            dump(job, to: &all)
            all += String(reflecting: job)
            for word in words {
                XCTAssertFalse(all.localizedCaseInsensitiveContains(word), "\(job.name) holds \(word)", file: file, line: line)
            }
        }
    }
}
