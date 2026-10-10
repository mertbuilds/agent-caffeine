import Foundation

/// Finds the launchd agents of the user that run by a calendar:
/// `~/Library/LaunchAgents/*.plist` with `StartCalendarInterval`, as XML
/// or as a binary plist.
///
/// Of each plist only `Label`, `Disabled`, `KeepAlive` and
/// `StartCalendarInterval` are looked at, and only the label and the
/// times are kept. The program, its arguments and its environment are
/// never taken out of the plist.
///
/// Not offered:
///
/// - `StartInterval` jobs. launchd loses an interval that passes while
///   the Mac sleeps, and it counts from the moment the job was loaded,
///   which no file says. So no next run can be worked out, and a wake
///   would not bring the lost run back.
/// - Jobs with only `RunAtLoad` or `WatchPaths`: they have no time.
/// - `KeepAlive` jobs: they run all the time.
/// - `Disabled` jobs, and labels of Apple.
struct LaunchAgentsJobReader {
    static let folder = "Library/LaunchAgents"
    static let idLimit = 120

    /// The home folder of the user.
    var home: URL

    func read(_ access: JobSourceAccess) -> JobSourceReading {
        let folder = home.appendingPathComponent(Self.folder)
        let names: [String]
        switch access.fileNames(in: folder) {
        case .found(let found): names = found
        case .missing: return JobSourceReading(source: .launchd, jobs: [])
        case .failed(let reason): return JobSourceReading(source: .launchd, unreadable: reason)
        }
        var jobs: [ScheduledJob] = []
        for name in names.sorted() where name.hasSuffix(".plist") && !name.hasPrefix(".") {
            // A plist that cannot be read is one job less, not a failure.
            guard case .found(let data) = access.data(at: folder.appendingPathComponent(name)),
                  let job = Self.job(plist: data, fileName: name), !jobs.contains(where: { $0.id == job.id }) else { continue }
            jobs.append(job)
        }
        return JobSourceReading(source: .launchd, jobs: jobs)
    }

    /// Nil for a plist that is not offered, see above.
    static func job(plist data: Data, fileName: String) -> ScheduledJob? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return nil }
        if plist["Disabled"] as? Bool == true { return nil }
        if plist["KeepAlive"] as? Bool == true || plist["KeepAlive"] is [String: Any] { return nil }
        guard let entries = LaunchdCalendar.entries(plist[LaunchdCalendar.key]) else { return nil }
        let fromFile = (fileName as NSString).deletingPathExtension
        guard let label = ManualHold.clean(plist["Label"] as? String ?? fromFile, limit: idLimit) else { return nil }
        if label.lowercased().hasPrefix("com.apple.") { return nil }
        return ScheduledJob(
            id: "launchd:" + label, source: .launchd, name: String(label.prefix(ScheduledJob.nameLimit)), schedule: .calendar(entries)
        )
    }
}
