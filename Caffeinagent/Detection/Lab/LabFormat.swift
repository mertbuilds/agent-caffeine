import Foundation

/// What the owner saw an agent do, to score the detection against.
enum LabTruth: String, Codable, CaseIterable {
    case working
    case waiting
    case idle
    case gone
}

/// The first line of a recording.
struct LabHeader: Codable, Equatable {
    var label: String
    var startedAt: Date
    /// `AppVersion.current`.
    var app: String
    var os: String
    /// `hw.model`, such as "Mac16,1".
    var model: String
    var catalog = AgentCatalog.version
    var frameVersion = EvidenceFrame.currentVersion
    /// `AwakeMode.rawValue`.
    var mode: String
    var settings: DetectionSettings
    /// The most seconds a replay of this recording may hold the Mac awake
    /// wrongly. `LabReplayTests` reads it. Without it the budget is zero.
    var wronglyHeldBudget: TimeInterval?
}

struct LabMark: Codable, Equatable {
    /// Every agent.
    static let allAgents = "*"

    var at: Date
    /// An `AgentDefinition.id` for every instance of that agent together,
    /// `id:pid` for one instance, or `*`.
    var agent: String
    var truth: LabTruth
    var note: String?
}

/// The verdict the app gave live, next to the evidence it came from.
struct LabVerdict: Codable, Equatable {
    var id: String
    var pid: Int32
    var state: WorkState
    /// `VerdictReason.code`.
    var why: String
    /// `HoldCause.code`, nil when the instance did not hold.
    var hold: String?
}

struct LabHold: Codable, Equatable {
    var on: Bool
    var lid: Bool
    var headline: String
}

/// One line of a recording: a header, a mark, or a sample.
struct LabLine: Codable, Equatable {
    var header: LabHeader?
    var mark: LabMark?
    var frame: EvidenceFrame?
    var verdicts: [LabVerdict]?
    var hold: LabHold?
    /// Milliseconds the sample cost.
    var ms: Double?
}

struct LabSample: Equatable {
    var frame: EvidenceFrame
    var verdicts: [LabVerdict] = []
    var hold: LabHold?
    var ms: Double?
}

struct LabRecording: Equatable {
    var header: LabHeader?
    var samples: [LabSample] = []
    var marks: [LabMark] = []
}

enum LabFormat {
    /// Times are seconds since the epoch with milliseconds, short enough for
    /// a line per sample and exact enough to replay.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode((date.timeIntervalSince1970 * 1000).rounded() / 1000)
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    static func line(_ line: LabLine) throws -> Data {
        var data = try encoder().encode(line)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    /// A recording holds no user content by construction: evidence carries
    /// states, counts and times. The names are the only free text, and a
    /// name the user gave as a path is cut to its last part. What a hold
    /// from the command line is for is the caller's own text, and is left
    /// out. A job hold keeps its source and its times: the name of the
    /// job, which is in its ids too, is left out.
    static func scrubbed(_ frame: EvidenceFrame) -> EvidenceFrame {
        var frame = frame
        for index in frame.jobHolds.indices {
            let source = frame.jobHolds[index].source.rawValue
            frame.jobHolds[index].name = source
            frame.jobHolds[index].jobID = "\(source):\(index + 1)"
            frame.jobHolds[index].id = "\(source):\(index + 1)@\(Int(frame.jobHolds[index].fireAt))"
        }
        for index in frame.holds.indices {
            frame.holds[index].reason = nil
            frame.holds[index].command = frame.holds[index].command.map(withoutPath)
        }
        for index in frame.agents.indices {
            frame.agents[index].agentID = withoutPath(frame.agents[index].agentID)
            frame.agents[index].displayName = withoutPath(frame.agents[index].displayName)
            if let detail = frame.agents[index].reported?.detail { frame.agents[index].reported?.detail = withoutPath(detail) }
        }
        return frame
    }

    /// The header's free text: the label, and the agent names the user
    /// added, which are also the keys of their rules.
    static func scrubbed(_ header: LabHeader) -> LabHeader {
        var header = header
        header.label = withoutPath(header.label)
        header.settings.userAgentNames = header.settings.userAgentNames.map(withoutPath)
        header.settings.agentRules = Dictionary(header.settings.agentRules.map { (withoutPath($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        return header
    }

    static func withoutPath(_ text: String) -> String {
        guard let slash = text.lastIndex(of: "/") else { return text }
        let prefix = text.hasPrefix("user:") ? "user:" : ""
        return prefix + String(text[text.index(after: slash)...])
    }

    static func sample(frame: EvidenceFrame, decision: HoldDecision, cost: TimeInterval?) -> LabLine {
        let verdicts = decision.perAgent.map { hold in
            LabVerdict(
                id: withoutPath(hold.reading.agentID), pid: hold.reading.identity.pid, state: hold.reading.verdict.state,
                why: hold.reading.verdict.reason.code, hold: hold.cause?.code
            )
        }
        var headline = decision.headline.text
        for name in decision.perAgent.map(\.reading.displayName) where name.contains("/") {
            headline = headline.replacingOccurrences(of: name, with: withoutPath(name))
        }
        if case .manualHold = decision.headline { headline = "Awake: a hold from the command line" }
        return LabLine(
            frame: scrubbed(frame), verdicts: verdicts,
            hold: LabHold(on: decision.hold, lid: decision.lidClosedFlag, headline: headline),
            ms: cost.map { ($0 * 100_000).rounded() / 100 }
        )
    }

    /// Reads the text of a recording. A last line that was cut off by a kill
    /// is left out; any other line that cannot be read is an error.
    static func recording(from text: String) throws -> LabRecording {
        var recording = LabRecording()
        let decoder = decoder()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for (index, text) in lines.enumerated() {
            let line: LabLine
            do {
                line = try decoder.decode(LabLine.self, from: Data(text.utf8))
            } catch {
                if index == lines.count - 1 { break }
                throw LabError.unreadableLine(index + 1)
            }
            if let header = line.header { recording.header = recording.header ?? header }
            if let mark = line.mark { recording.marks.append(mark) }
            if let frame = line.frame {
                recording.samples.append(LabSample(frame: frame, verdicts: line.verdicts ?? [], hold: line.hold, ms: line.ms))
            }
        }
        recording.marks.sort { $0.at < $1.at }
        return recording
    }

    static func recording(at url: URL) throws -> LabRecording {
        try recording(from: String(decoding: Data(contentsOf: url), as: UTF8.self))
    }
}

enum LabError: Error, Equatable, CustomStringConvertible {
    case unreadableLine(Int)
    case noRecording
    case cannotWrite(String)

    var description: String {
        switch self {
        case .unreadableLine(let number): return "Line \(number) of the recording cannot be read."
        case .noRecording: return "No recording is running. Start one with --lab-record."
        case .cannotWrite(let path): return "Cannot write to \(path)."
        }
    }
}

extension VerdictReason {
    /// A short stable name for a recording. `text` is for the menu.
    var code: String {
        switch self {
        case .reportsBusy: return "reportsBusy"
        case .runningCommand(let count): return "runningCommand:\(count)"
        case .backgroundJob(let count): return "backgroundJob:\(count)"
        case .holdsSleepAssertion: return "holdsSleepAssertion"
        case .writingSessionFile(let seconds): return "writingSessionFile:\(seconds)"
        case .workedRecently(let seconds): return "workedRecently:\(seconds)"
        case .cpuActivity: return "cpuActivity"
        case .asksPermission: return "asksPermission"
        case .awaitsApproval: return "awaitsApproval"
        case .atPrompt: return "atPrompt"
        case .noActivity(let minutes): return "noActivity:\(minutes)"
        case .onlyWeakSigns(let minutes): return "onlyWeakSigns:\(minutes)"
        case .alwaysWorkingByRule: return "alwaysWorkingByRule"
        case .ignoredByRule: return "ignoredByRule"
        }
    }
}

extension HoldCause {
    var code: String {
        switch self {
        case .working: return "working"
        case .waitingForUser: return "waiting"
        case .finishedRecently: return "finished"
        case .open: return "open"
        }
    }
}
