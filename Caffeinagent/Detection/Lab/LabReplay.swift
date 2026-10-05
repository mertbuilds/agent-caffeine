import Foundation

/// One replayed sample.
struct LabStep: Equatable {
    var at: Date
    var readings: [AgentReading]
    var decision: HoldDecision
}

struct LabScore: Equatable {
    /// How long the detection took to follow one mark.
    struct Reaction: Equatable {
        var at: Date
        var truth: LabTruth
        /// Seconds from the mark to the first sample that agrees with it.
        /// Nil when no sample agreed before the next mark.
        var delay: TimeInterval?
    }

    /// The score of one mark target: an agent, one instance, or `*`.
    struct Agent: Equatable {
        var agent: String
        /// Seconds the target held the Mac awake though the truth was idle,
        /// gone, or waiting for longer than the waiting hold. The release
        /// time after the mark is allowed and does not count.
        var wronglyHeld: TimeInterval = 0
        /// Seconds the target did not hold though the truth was working.
        var wronglyReleased: TimeInterval = 0
        var reactions: [Reaction] = []
    }

    /// What the replay made of one instance, marks or not.
    struct Seen: Equatable {
        var agentID: String
        var displayName: String
        var pid: Int32
        var working: TimeInterval = 0
        var waiting: TimeInterval = 0
        var idle: TimeInterval = 0
        var held: TimeInterval = 0
    }

    var title: String
    var samples: Int
    var duration: TimeInterval
    var marks: Int
    var agents: [Agent]
    var seen: [Seen]
    /// Seconds the Mac was held awake in the replay.
    var heldSeconds: TimeInterval
    /// Samples where the replay holds and the app did not, or the reverse.
    /// Not zero is normal when the settings or the rules changed.
    var liveMismatches: Int

    var wronglyHeld: TimeInterval { agents.reduce(0) { $0 + $1.wronglyHeld } }
    var wronglyReleased: TimeInterval { agents.reduce(0) { $0 + $1.wronglyReleased } }

    var report: String {
        var lines = ["Lab score: \(title)"]
        lines.append("\(samples) samples over \(Self.seconds(duration)), \(marks) marks, Mac held awake for \(Self.seconds(heldSeconds))")
        for seen in seen {
            lines.append("  \(seen.displayName) [\(seen.agentID):\(seen.pid)]: working \(Self.seconds(seen.working)), waiting \(Self.seconds(seen.waiting)), idle \(Self.seconds(seen.idle)), held \(Self.seconds(seen.held))")
        }
        if agents.isEmpty { lines.append("No marks, so nothing to score.") }
        for agent in agents {
            lines.append("\(agent.agent): wrongly held \(Self.seconds(agent.wronglyHeld)), wrongly released \(Self.seconds(agent.wronglyReleased))")
            for reaction in agent.reactions {
                let delay = reaction.delay.map { "seen after \(Self.seconds($0))" } ?? "never seen"
                lines.append("  \(Self.clock.string(from: reaction.at)) \(reaction.truth.rawValue): \(delay)")
            }
        }
        if !agents.isEmpty {
            lines.append("Total: wrongly held \(Self.seconds(wronglyHeld)), wrongly released \(Self.seconds(wronglyReleased))")
        }
        lines.append("The replay differs from the live decision in \(liveMismatches) of \(samples) samples")
        return lines.joined(separator: "\n")
    }

    private static func seconds(_ value: TimeInterval) -> String {
        String(format: "%.1f s", value)
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

/// Runs a recording through `VerdictRules` and `HoldPolicy` again and scores
/// the result against the owner's marks. Pure.
enum LabReplay {
    /// The settings and the mode are the recorded ones unless given. The
    /// replay runs switched on, with no license and no safety stop.
    static func steps(of recording: LabRecording, settings: DetectionSettings? = nil, mode: AwakeMode? = nil) -> [LabStep] {
        let settings = settings ?? recording.header?.settings ?? DetectionSettings()
        let mode = mode ?? recording.header.flatMap { AwakeMode(rawValue: $0.mode) } ?? .agentWorking
        var agentMemory: [ProcessIdentity: AgentMemory] = [:]
        var policyMemory = PolicyMemory()
        var previousAt: Date?
        return recording.samples.map { sample in
            // As the engine does.
            if let gap = SampleGap.length(from: previousAt, to: sample.frame.at) {
                agentMemory = agentMemory.mapValues { $0.shifted(by: gap) }
                policyMemory = policyMemory.shifted(by: gap)
            }
            previousAt = sample.frame.at
            let (readings, nextAgents) = VerdictRules.readings(for: sample.frame, memory: agentMemory, settings: settings)
            let (decision, nextPolicy) = HoldPolicy.decide(
                readings: readings, memory: policyMemory, mode: mode, enabled: true, entitlement: nil, safety: nil,
                settings: settings, context: sample.frame.context, now: sample.frame.at
            )
            agentMemory = nextAgents
            policyMemory = nextPolicy
            return LabStep(at: sample.frame.at, readings: readings, decision: decision)
        }
    }

    static func score(_ recording: LabRecording, settings: DetectionSettings? = nil, mode: AwakeMode? = nil) -> LabScore {
        let used = settings ?? recording.header?.settings ?? DetectionSettings()
        let steps = steps(of: recording, settings: used, mode: mode)
        var targets: [String] = []
        for mark in recording.marks where !targets.contains(mark.agent) { targets.append(mark.agent) }
        let agents = targets.map { target in
            score(target: target, marks: recording.marks.filter { $0.agent == target }.sorted { $0.at < $1.at }, steps: steps, settings: used)
        }
        var mismatches = 0
        for (step, sample) in zip(steps, recording.samples) {
            if let live = sample.hold, live.on != step.decision.hold { mismatches += 1 }
        }
        let duration = steps.last.flatMap { last in steps.first.map { last.at.timeIntervalSince($0.at) } } ?? 0
        return LabScore(
            title: title(of: recording), samples: steps.count, duration: duration, marks: recording.marks.count, agents: agents,
            seen: seen(in: steps), heldSeconds: spans(of: steps).reduce(0) { $0 + ($1.step.decision.hold ? $1.end.timeIntervalSince($1.step.at) : 0) },
            liveMismatches: mismatches
        )
    }

    private static func title(of recording: LabRecording) -> String {
        guard let header = recording.header else { return "recording without a header" }
        return "\(header.label) (\(header.app), macOS \(header.os), \(header.model))"
    }

    /// Each step lasts until the next one. The last step has no length.
    private static func spans(of steps: [LabStep]) -> [(step: LabStep, end: Date)] {
        steps.indices.map { (steps[$0], $0 + 1 < steps.count ? steps[$0 + 1].at : steps[$0].at) }
    }

    // MARK: Targets

    private static func matches(_ reading: AgentReading, target: String) -> Bool {
        if target == LabMark.allAgents { return true }
        if let colon = target.lastIndex(of: ":"), let pid = Int32(target[target.index(after: colon)...]) {
            return reading.agentID == target[..<colon] && reading.identity.pid == pid
        }
        return reading.agentID == target
    }

    private static func isHeld(_ step: LabStep, target: String) -> Bool {
        guard step.decision.hold else { return false }
        if target == LabMark.allAgents { return true }
        return step.decision.perAgent.contains { $0.cause != nil && matches($0.reading, target: target) }
    }

    /// The instances of a target together: working when one works, else
    /// waiting when one waits. Gone when the frame has none of them.
    private static func state(of step: LabStep, target: String) -> LabTruth {
        let states = step.readings.filter { matches($0, target: target) }.map(\.verdict.state)
        if states.isEmpty { return .gone }
        if states.contains(.working) { return .working }
        return states.contains(.waitingForUser) ? .waiting : .idle
    }

    /// An agent that went away is as good as idle.
    private static func agrees(_ state: LabTruth, with truth: LabTruth) -> Bool {
        state == truth || (truth == .idle && state == .gone)
    }

    /// How long a hold may last after the truth changed to not working.
    private static func allowedHold(after truth: LabTruth, target: String, steps: [LabStep], settings: DetectionSettings) -> TimeInterval {
        let levels = steps.lazy.flatMap(\.readings).filter { matches($0, target: target) }.map(\.level)
        let release: TimeInterval
        if target == LabMark.allAgents {
            release = max(settings.releaseAfterState, settings.releaseAfterActivity)
        } else {
            release = levels.first.map { $0 == .state ? settings.releaseAfterState : settings.releaseAfterActivity } ?? settings.releaseAfterState
        }
        return truth == .waiting ? max(settings.waitingHold, release) : release
    }

    private static func score(target: String, marks: [LabMark], steps: [LabStep], settings: DetectionSettings) -> LabScore.Agent {
        var result = LabScore.Agent(agent: target)
        let spans = spans(of: steps)
        for (index, mark) in marks.enumerated() {
            let until = index + 1 < marks.count ? marks[index + 1].at : Date.distantFuture
            let allowedUntil = mark.at.addingTimeInterval(allowedHold(after: mark.truth, target: target, steps: steps, settings: settings))
            for span in spans {
                let from = max(span.step.at, mark.at)
                let to = min(span.end, until)
                guard to > from else { continue }
                let held = isHeld(span.step, target: target)
                if mark.truth == .working {
                    if !held { result.wronglyReleased += to.timeIntervalSince(from) }
                } else if held, to > allowedUntil {
                    result.wronglyHeld += to.timeIntervalSince(max(from, allowedUntil))
                }
            }
            result.reactions.append(LabScore.Reaction(at: mark.at, truth: mark.truth, delay: reactionDelay(to: mark, until: until, target: target, steps: steps)))
        }
        return result
    }

    /// Zero when the samples on both sides of the mark already agree with it.
    private static func reactionDelay(to mark: LabMark, until: Date, target: String, steps: [LabStep]) -> TimeInterval? {
        guard let first = steps.firstIndex(where: { $0.at >= mark.at }) else { return nil }
        for index in first..<steps.count where steps[index].at < until {
            guard agrees(state(of: steps[index], target: target), with: mark.truth) else { continue }
            let agreedBefore = index == first && first > 0 && agrees(state(of: steps[first - 1], target: target), with: mark.truth)
            return agreedBefore ? 0 : steps[index].at.timeIntervalSince(mark.at)
        }
        return nil
    }

    private static func seen(in steps: [LabStep]) -> [LabScore.Seen] {
        var order: [ProcessIdentity] = []
        var byIdentity: [ProcessIdentity: LabScore.Seen] = [:]
        for span in spans(of: steps) {
            let length = span.end.timeIntervalSince(span.step.at)
            for hold in span.step.decision.perAgent {
                let reading = hold.reading
                if byIdentity[reading.identity] == nil { order.append(reading.identity) }
                var seen = byIdentity[reading.identity] ?? LabScore.Seen(agentID: reading.agentID, displayName: reading.displayName, pid: reading.identity.pid)
                switch reading.verdict.state {
                case .working: seen.working += length
                case .waitingForUser: seen.waiting += length
                case .idle: seen.idle += length
                }
                if hold.cause != nil { seen.held += length }
                byIdentity[reading.identity] = seen
            }
        }
        return order.compactMap { byIdentity[$0] }
    }
}
