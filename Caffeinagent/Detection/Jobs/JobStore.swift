import Foundation
import os

/// Reads the three sources of scheduled jobs and tells its owner when
/// what it found changes: every few minutes, and when the folder of the
/// launchd agents or the jobs file of Hermes Agent changes, the way the
/// collector watches the holds folder.
///
/// It runs only while "Wake for jobs" is on, so nothing is read on a Mac
/// whose user did not ask for it. The jobs come as the readers give
/// them, all switched off: the owner applies the switches of the user.
///
/// Privacy: the readers keep the times and a short name of each job.
/// The log gets counts and no name.
final class JobStore {
    /// A crontab has no file that can be watched, so this is how late a
    /// new line of it can be seen.
    static let interval: TimeInterval = 300
    /// A file that is saved brings several events. One reading follows.
    static let settle: TimeInterval = 1
    /// How often a path that is not there is looked for again.
    static let watchRetry: TimeInterval = 30

    private let access: JobSourceAccess
    private let home: URL
    private let timeZone: () -> TimeZone
    private let queue = DispatchQueue(label: "com.caffeinagent.app.jobs", qos: .utility)
    private let log = Logger(subsystem: "com.caffeinagent.app", category: "JobStore")
    private var onChange: (([JobSourceReading]) -> Void)?
    private var timer: DispatchSourceTimer?
    private var watches: [FileWatch] = []
    private var last: [JobSourceReading]?
    private var readPending = false

    init(access: JobSourceAccess, home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true), timeZone: @escaping () -> TimeZone = { .current }) {
        self.access = access
        self.home = home
        self.timeZone = timeZone
    }

    deinit {
        timer?.cancel()
        watches.forEach { $0.cancel() }
    }

    /// The paths that bring a new reading when they change.
    static func watched(home: URL) -> [URL] {
        [home.appendingPathComponent(LaunchAgentsJobReader.folder), home.appendingPathComponent(HermesJobReader.file)]
    }

    /// One reading of every source, in the order of `ScheduledJob.Source`.
    static func read(access: JobSourceAccess, home: URL, timeZone: TimeZone) -> [JobSourceReading] {
        [
            LaunchAgentsJobReader(home: home).read(access),
            CrontabJobReader().read(access),
            HermesJobReader(home: home).read(access, timeZone: timeZone),
        ]
    }

    /// Reads at once and from then on. `onChange` runs on the main
    /// thread: with the first reading, and with each one that differs
    /// from the one before it.
    func start(onChange: @escaping ([JobSourceReading]) -> Void) {
        queue.async { [self] in
            guard timer == nil else { return }
            self.onChange = onChange
            last = nil
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: Self.interval, leeway: .seconds(30))
            timer.setEventHandler { [weak self] in self?.read() }
            timer.resume()
            self.timer = timer
            watches = Self.watched(home: home).map { url in
                FileWatch(url: url, queue: queue, retryInterval: Self.watchRetry) { [weak self] _ in self?.readSoon() }
            }
            watches.forEach { $0.start() }
        }
    }

    /// Nothing is read and nothing is told from here on.
    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            watches.forEach { $0.cancel() }
            watches = []
            onChange = nil
            last = nil
            readPending = false
        }
    }

    /// For Settings when it opens: the crontab may have a new line.
    func refresh() {
        queue.async { [weak self] in self?.readSoon() }
    }

    private func readSoon() {
        guard timer != nil, !readPending else { return }
        readPending = true
        queue.asyncAfter(deadline: .now() + Self.settle) { [weak self] in
            guard let self, self.readPending else { return }
            self.readPending = false
            self.read()
        }
    }

    private func read() {
        guard let onChange else { return }
        let readings = Self.read(access: access, home: home, timeZone: timeZone())
        guard readings != last else { return }
        last = readings
        log.info("\(Self.logLine(readings), privacy: .public)")
        DispatchQueue.main.async { onChange(readings) }
    }

    /// "jobs: launchd 2, crontab 0, hermes unreadable". Counts only.
    static func logLine(_ readings: [JobSourceReading]) -> String {
        let parts = readings.map { reading -> String in
            if case .unreadable = reading.status { return "\(reading.source.rawValue) unreadable" }
            return "\(reading.source.rawValue) \(reading.jobs.count)"
        }
        return "jobs: " + parts.joined(separator: ", ")
    }
}
