import Foundation

/// Runs a recording through the verdicts and `AgentNoticeReducer`, with
/// both notifications on and "only when not in front" off, and lists each
/// change of each session with what the reducer made of it. Pure. The
/// lines hold pids, states and times.
enum LabNotices {
    static func lines(_ recording: LabRecording, settings: DetectionSettings? = nil) -> [String] {
        let steps = LabReplay.steps(of: recording, settings: settings)
        guard let start = steps.first?.at else { return [] }
        var reducer = AgentNoticeReducer()
        var seen: [ProcessIdentity: (turn: WorkState?, verdict: WorkState, since: Date)] = [:]
        var lines: [String] = []
        func time(_ at: Date) -> String { String(format: "%7.1f s", at.timeIntervalSince(start)) }
        for (index, step) in steps.enumerated() {
            var next: [ProcessIdentity: (turn: WorkState?, verdict: WorkState, since: Date)] = [:]
            for reading in step.readings {
                let identity = reading.identity
                let now = (turn: reading.turn?.state, verdict: reading.verdict.state, since: step.at)
                guard let old = seen[identity] else {
                    if index > 0 { lines.append("\(time(step.at))  pid \(identity.pid)  new, \(words(now.turn, now.verdict))") }
                    next[identity] = now
                    continue
                }
                if old.turn == now.turn, old.verdict == now.verdict {
                    next[identity] = old
                    continue
                }
                let lasted = String(format: "%.1f s", step.at.timeIntervalSince(old.since))
                let told = (old.turn ?? old.verdict) != (now.turn ?? now.verdict)
                lines.append(
                    "\(time(step.at))  pid \(identity.pid)  \(words(old.turn, old.verdict)) -> \(words(now.turn, now.verdict)) (\(reading.verdict.reason.code)) after \(lasted)"
                        + (told ? "" : ": no change for the notifications")
                )
                next[identity] = now
            }
            for (identity, old) in seen where next[identity] == nil {
                lines.append("\(time(step.at))  pid \(identity.pid)  \(words(old.turn, old.verdict)) -> gone")
            }
            seen = next
            let settings = AgentNoticeSettings(waiting: true, finished: true, onlyWhenAway: false)
            _ = reducer.update(AgentNoticeInput(readings: step.readings, settings: settings), now: step.at)
            lines += reducer.decisions.map { "\(time(step.at))    \($0.logLine)" }
        }
        return lines
    }

    static func report(_ recording: LabRecording) -> String {
        let lines = lines(recording)
        let fired = lines.filter { $0.contains(" fired pid ") }.count
        return (["Agent notifications in the replay: \(fired) fired"] + (lines.isEmpty ? ["No session changed."] : lines)).joined(separator: "\n")
    }

    private static func words(_ turn: WorkState?, _ verdict: WorkState) -> String {
        guard let turn else { return "\(name(verdict)) (no turn reported)" }
        return turn == verdict ? name(turn) : "turn \(name(turn)), verdict \(name(verdict))"
    }

    private static func name(_ state: WorkState) -> String {
        switch state {
        case .working: return "working"
        case .waitingForUser: return "waiting"
        case .idle: return "idle"
        }
    }
}
