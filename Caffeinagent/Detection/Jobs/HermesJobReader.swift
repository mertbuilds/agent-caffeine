import Foundation

/// Finds the cron jobs of Hermes Agent in `~/.hermes/cron/jobs.json`.
///
/// The file has the key `jobs` with a list. Of each job these fields are
/// read: `id`, `name`, `enabled`, `state`, `paused_at`, `next_run_at`,
/// `schedule` (`kind`, `expr`, `minutes`, `display`) and
/// `schedule_display`. The prompt, the model and every other field are
/// never taken out of the file.
///
/// The format is private to Hermes and has no version. So every field
/// can be missing or of another type, fields that are not known are
/// passed over, and a file that cannot be understood gives no job and a
/// reason, never a crash.
///
/// A job that is switched off or paused is not offered. Hermes writes
/// the next run itself, and that time is used while it is ahead, see
/// `ReportedSchedule`.
struct HermesJobReader {
    static let file = ".hermes/cron/jobs.json"
    static let idLimit = 64

    /// The home folder of the user.
    var home: URL

    /// - Parameter timeZone: for a time that Hermes wrote without one.
    func read(_ access: JobSourceAccess, timeZone: TimeZone) -> JobSourceReading {
        switch access.data(at: home.appendingPathComponent(Self.file)) {
        case .found(let data):
            let (jobs, reason) = Self.jobs(data, timeZone: timeZone)
            return reason.map { JobSourceReading(source: .hermes, unreadable: $0) } ?? JobSourceReading(source: .hermes, jobs: jobs)
        case .missing: return JobSourceReading(source: .hermes, jobs: [])
        case .failed(let reason): return JobSourceReading(source: .hermes, unreadable: reason)
        }
    }

    /// The jobs, or no job and why the file was not understood.
    static func jobs(_ data: Data, timeZone: TimeZone) -> (jobs: [ScheduledJob], reason: String?) {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return ([], "jobs.json is no JSON") }
        guard let list = (root as? [String: Any])?["jobs"] as? [Any] ?? root as? [Any] else { return ([], "jobs.json has no list of jobs") }
        var jobs: [ScheduledJob] = []
        for case let record as [String: Any] in list {
            guard let job = job(record, timeZone: timeZone), !jobs.contains(where: { $0.id == job.id }) else { continue }
            jobs.append(job)
        }
        return (jobs, nil)
    }

    static func job(_ record: [String: Any], timeZone: TimeZone) -> ScheduledJob? {
        if record["enabled"] as? Bool == false { return nil }
        if let paused = record["paused_at"], !(paused is NSNull) { return nil }
        if (record["state"] as? String)?.lowercased() == "paused" { return nil }
        let id = text(record["id"]), name = text(record["name"])
        guard let key = ManualHold.clean(id ?? name, limit: idLimit),
              let shown = ManualHold.clean(name ?? id, limit: ScheduledJob.nameLimit) else { return nil }

        var schedule = ReportedSchedule(nextRun: date(record["next_run_at"], timeZone: timeZone))
        let details = record["schedule"] as? [String: Any]
        let texts = [details?["expr"], record["schedule"], details?["display"], record["schedule_display"]].compactMap { $0 as? String }
        schedule.cron = texts.lazy.compactMap(CronExpression.parse).first
        if let minutes = (details?["minutes"] as? NSNumber)?.intValue, minutes > 0 {
            schedule.everyMinutes = minutes
        } else {
            schedule.everyMinutes = texts.lazy.compactMap(minutes(ofInterval:)).first
        }
        guard schedule.nextRun != nil || schedule.cron != nil || schedule.everyMinutes != nil else { return nil }
        return ScheduledJob(id: "hermes:" + key, source: .hermes, name: shown, schedule: .reported(schedule))
    }

    /// 360 for "every 360m", and for "every 6h".
    static func minutes(ofInterval text: String) -> Int? {
        let words = text.lowercased().split(separator: " ")
        guard words.count == 2, words[0] == "every", let unit = words[1].last, let count = Int(words[1].dropLast()), count > 0,
              count <= 100_000 else { return nil }
        switch unit {
        case "m": return count
        case "h": return count * 60
        case "d": return count * 1440
        default: return nil
        }
    }

    /// A time as ISO 8601 text, with or without parts of a second and
    /// with or without a time zone, or as seconds or milliseconds since
    /// the epoch. Nil for anything else, and for a year far from now.
    static func date(_ value: Any?, timeZone: TimeZone) -> Date? {
        var date: Date?
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let seconds = number.doubleValue
            date = seconds.isFinite ? Date(timeIntervalSince1970: seconds > 100_000_000_000 ? seconds / 1000 : seconds) : nil
        } else if let raw = value as? String {
            var text = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "T")
            text = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
            let formatter = ISO8601DateFormatter()
            if text.range(of: #"(Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil {
                formatter.formatOptions = [.withInternetDateTime]
            } else {
                formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
                formatter.timeZone = timeZone
            }
            date = formatter.date(from: text)
        }
        guard let date, (946_684_800...4_102_444_800).contains(date.timeIntervalSince1970) else { return nil }
        return date
    }

    private static func text(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.stringValue }
        return nil
    }
}
