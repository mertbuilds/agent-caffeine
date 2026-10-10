import Foundation

/// What a look at a file, a folder or a command gave.
enum JobSourceRead<Value> {
    case found(Value)
    /// Not there: no such file or folder, no crontab.
    case missing
    /// There, and it could not be read. The text says why, for Settings.
    case failed(String)
}

/// How the readers of scheduled jobs reach the disk and the crontab. The
/// app passes the real thing and the tests pass fixtures, so no test
/// reads the files of the person who runs it.
protocol JobSourceAccess {
    /// The names of the files in a folder, without the folder.
    func fileNames(in folder: URL) -> JobSourceRead<[String]>
    func data(at file: URL) -> JobSourceRead<Data>
    /// What `/usr/bin/crontab -l` prints. See `CrontabJobReader.output`.
    func crontab() -> JobSourceRead<String>
}

enum JobSourceStatus: Equatable {
    /// Jobs were found.
    case ok
    /// The source is not there, or it has no job with a time.
    case none
    /// The source is there and could not be read or understood. No job
    /// is taken from it. The text says why, and holds nothing of the
    /// content.
    case unreadable(String)

    static let reasonLimit = 80

    static func unreadable(reason: String) -> JobSourceStatus {
        .unreadable(ManualHold.clean(reason, limit: reasonLimit) ?? "It could not be read")
    }
}

/// The jobs of one source, all switched off, and how the reading went.
struct JobSourceReading: Equatable {
    var source: ScheduledJob.Source
    var jobs: [ScheduledJob] = []
    var status: JobSourceStatus

    init(source: ScheduledJob.Source, jobs: [ScheduledJob]) {
        self.source = source
        self.jobs = jobs
        status = jobs.isEmpty ? .none : .ok
    }

    init(source: ScheduledJob.Source, unreadable reason: String) {
        self.source = source
        status = .unreadable(reason: reason)
    }
}
