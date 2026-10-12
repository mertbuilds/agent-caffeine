import Darwin
import Foundation

/// The detection lab from the command line, until the app has a window for
/// it. None of these starts the menu bar app or takes a power assertion.
///
///     caffeinagent --lab-record <label>                 record until SIGINT or SIGTERM
///     caffeinagent --lab-mark <agent> <truth> [note]    mark the running recording
///     caffeinagent --lab-score <file>                   replay a recording and score it
///     caffeinagent --lab-notices <file>                 replay a recording and list the agent notifications
///
/// `<agent>` is an agent id from the catalog (`claude`, `codex-desktop`),
/// `id:pid` for one instance, or `*`. `<truth>` is `working`, `waiting`,
/// `idle` or `gone`.
enum LabCommand {
    private static var engine: DetectionEngine?
    private static var signals: [DispatchSourceSignal] = []

    /// False when the arguments hold no lab command. A command that
    /// finishes ends the process, and recording never returns.
    @MainActor
    static func run(_ arguments: [String]) -> Bool {
        guard let index = arguments.firstIndex(where: { $0.hasPrefix("--lab-") }) else { return false }
        let rest = Array(arguments[(index + 1)...])
        switch arguments[index] {
        case "--lab-record":
            record(label: rest.first ?? "recording")
        case "--lab-mark":
            guard rest.count >= 2, let truth = LabTruth(rawValue: rest[1]) else {
                fail("Usage: --lab-mark <agent> <working|waiting|idle|gone> [note]")
            }
            mark(agent: rest[0], truth: truth, note: rest.count > 2 ? rest[2...].joined(separator: " ") : nil)
        case "--lab-score":
            guard let path = rest.first else { fail("Usage: --lab-score <file>") }
            score(path: path)
        case "--lab-notices":
            guard let path = rest.first else { fail("Usage: --lab-notices <file>") }
            notices(path: path)
        default:
            fail("Unknown lab command \(arguments[index]).")
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }

    private static func say(_ line: String) {
        print(line)
        fflush(stdout)
    }

    // MARK: Record

    @MainActor
    private static func record(label: String) -> Never {
        let engine = DetectionEngine.system()
        let recorder = LabRecorder()
        let header = LabHeader(
            label: label, startedAt: Date(), app: AppVersion.current,
            os: ProcessInfo.processInfo.operatingSystemVersionString, model: hardwareModel(),
            mode: engine.mode.rawValue, settings: engine.settings
        )
        let url: URL
        do {
            url = try recorder.start(label: label, header: header)
        } catch {
            fail("\(error)")
        }
        say("Recording to \(url.path)")

        var costs: [Double] = []
        let began = Date()
        engine.recorder = recorder
        // The closed lid limit, as the app and the replay have it. The
        // other safety stops are not in a recording.
        var closedLid = ClosedLidLimit()
        (closedLid.timeLimit, closedLid.dropLimit) = engine.settings.closedLidLimits()
        engine.onSample = { [weak engine] sample in
            costs.append(sample.cost * 1000)
            say(statusLine(sample))
            let stop = closedLid.update(sample.frame.context, holding: sample.decision.hold, at: sample.frame.time, afterGap: sample.afterGap)
            engine?.safety = stop.map(SafetyStop.closedLid)
        }
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler {
                recorder.stop()
                say(summary(url: url, costs: costs, seconds: Date().timeIntervalSince(began)))
                exit(0)
            }
            source.resume()
            signals.append(source)
        }
        Self.engine = engine
        engine.start()
        dispatchMain()
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// Time, hold, cost, then each agent with its state and reason.
    private static func statusLine(_ sample: DetectionSample) -> String {
        var parts = ["\(clock.string(from: sample.frame.at)) hold=\(sample.decision.hold ? "yes" : "no") \(String(format: "%.2f", sample.cost * 1000))ms"]
        for hold in sample.decision.perAgent {
            let reading = hold.reading
            let state: String
            switch reading.verdict.state {
            case .working: state = "working"
            case .waitingForUser: state = "waiting"
            case .idle: state = "idle"
            }
            let held = hold.cause.map { " holds:\($0.code)" } ?? ""
            parts.append("\(reading.agentID):\(reading.identity.pid) \(state) (\(reading.verdict.reason.code))\(held)")
        }
        if sample.decision.perAgent.isEmpty { parts.append("no agents") }
        return parts.joined(separator: " | ")
    }

    private static func summary(url: URL, costs: [Double], seconds: TimeInterval) -> String {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        let sorted = costs.sorted()
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        var lines = ["Stopped after \(String(format: "%.1f", seconds)) s and \(costs.count) samples."]
        if let low = sorted.first, let high = sorted.last {
            lines.append(String(format: "Sample cost: min %.2f ms, median %.2f ms, max %.2f ms.", low, sorted[sorted.count / 2], high))
        }
        if seconds > 0 {
            lines.append(String(format: "Process CPU: %.2f s, %.2f%% of one core.", cpu, cpu / seconds * 100))
            lines.append(String(format: "File: %d bytes, %.0f bytes per minute.", size, Double(size) / seconds * 60))
        }
        lines.append(url.path)
        return lines.joined(separator: "\n")
    }

    private static func hardwareModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: buffer)
    }

    // MARK: Mark and score

    private static func mark(agent: String, truth: LabTruth, note: String?) -> Never {
        guard let url = LabRecorder.runningRecording() else { fail("\(LabError.noRecording)") }
        do {
            try LabRecorder.appendMark(LabMark(at: Date(), agent: agent, truth: truth, note: note), to: url)
        } catch {
            fail("\(error)")
        }
        say("Marked \(agent) as \(truth.rawValue) in \(url.path)")
        exit(0)
    }

    private static func notices(path: String) -> Never {
        do {
            say(LabNotices.report(try LabFormat.recording(at: URL(fileURLWithPath: path))))
        } catch {
            fail("\(error)")
        }
        exit(0)
    }

    private static func score(path: String) -> Never {
        do {
            let recording = try LabFormat.recording(at: URL(fileURLWithPath: path))
            say(LabReplay.score(recording).report)
        } catch {
            fail("\(error)")
        }
        exit(0)
    }
}
