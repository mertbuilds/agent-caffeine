import Foundation
import os

@MainActor
final class ClaudeCodeWatcher: ObservableObject {
    @Published private(set) var agents: [DetectedAgent] = []

    private let projectsDir: URL
    private var eventStream: FSEventStreamRef?
    private let pollTimer: DispatchSourceTimer
    private let activeWindow: TimeInterval = 5
    private let idleWindow: TimeInterval = 300
    private let log = Logger(subsystem: "com.caffeinagent.app", category: "ClaudeCodeWatcher")

    init() {
        self.projectsDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/projects")
        self.pollTimer = DispatchSource.makeTimerSource(queue: .main)
        pollTimer.schedule(deadline: .now() + 1, repeating: 2.0)
        pollTimer.setEventHandler { [weak self] in self?.scan() }
        pollTimer.resume()
        startFSEvents()
        scan()
    }

    deinit {
        if let s = eventStream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
    }

    private func startFSEvents() {
        let path = projectsDir.path as CFString
        let paths = [path] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<ClaudeCodeWatcher>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in watcher.scan() }
            _ = count
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        eventStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        )
        if let s = eventStream {
            FSEventStreamSetDispatchQueue(s, .main)
            FSEventStreamStart(s)
        }
    }

    private func scan() {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            agents = []
            return
        }
        var found: [DetectedAgent] = []
        let now = Date()
        for projectDir in projectDirs where projectDir.hasDirectoryPath {
            guard let jsonls = try? fm.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            let project = projectLabel(projectDir.lastPathComponent)
            for url in jsonls where url.pathExtension == "jsonl" {
                guard let mtime = modificationDate(of: url) else { continue }
                let age = now.timeIntervalSince(mtime)
                guard age <= idleWindow else { continue }
                let parsed = Self.parseTail(of: url)
                let state = classify(age: age, turnInProgress: parsed.turnInProgress)
                let label = sessionLabel(project: project, file: url, title: parsed.title)
                found.append(DetectedAgent(
                    id: url.lastPathComponent,
                    source: .claudeCode,
                    label: label,
                    state: state,
                    lastActivity: mtime
                ))
            }
        }
        agents = found.sorted { $0.lastActivity > $1.lastActivity }
    }

    private func classify(age: TimeInterval, turnInProgress: Bool) -> AgentState {
        if age < activeWindow { return .active }
        if turnInProgress { return .active }
        return .waitingForInput
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    struct TailParse {
        var lastTurn: String?
        var turnInProgress = false
        var title: String?
    }

    /// Reads the last 16KB of a jsonl. A long last line, such as a big tool
    /// result, can fill that window, so without a turn in it the last 256KB
    /// are read before the session counts as waiting.
    nonisolated static func parseTail(of url: URL) -> TailParse {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return TailParse() }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return TailParse() }
        var result = TailParse()
        for chunk: UInt64 in [16_384, 262_144] {
            let offset = size > chunk ? size - chunk : 0
            try? handle.seek(toOffset: offset)
            guard let data = try? handle.readToEnd(), !data.isEmpty else { return TailParse() }
            result = parseTail(String(decoding: data, as: UTF8.self))
            if result.lastTurn != nil || offset == 0 { break }
        }
        return result
    }

    /// Finds the last user or assistant turn, skipping metadata lines such as
    /// `system` or `last-prompt`, plus the most recent `ai-title`. The turn is
    /// in progress after a user message or tool result, or while the assistant
    /// has a tool call running.
    nonisolated static func parseTail(_ text: String) -> TailParse {
        var result = TailParse()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines.reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = obj["type"] as? String else { continue }
            if result.lastTurn == nil, type == "user" || type == "assistant" {
                result.lastTurn = type
                result.turnInProgress = type == "user" || hasToolUse(obj["message"])
            }
            if result.title == nil, type == "ai-title", let t = obj["aiTitle"] as? String { result.title = t }
            if result.lastTurn != nil && result.title != nil { break }
        }
        return result
    }

    nonisolated private static func hasToolUse(_ message: Any?) -> Bool {
        guard let content = (message as? [String: Any])?["content"] as? [[String: Any]] else { return false }
        return content.contains { $0["type"] as? String == "tool_use" }
    }

    private func projectLabel(_ dirName: String) -> String {
        let raw = dirName.replacingOccurrences(of: "-Users-", with: "")
        return raw.split(separator: "-").last.map(String.init) ?? dirName
    }

    private func sessionLabel(project: String, file: URL, title: String?) -> String {
        if let title, !title.isEmpty {
            return "\(project) · \(title)"
        }
        let stem = file.deletingPathExtension().lastPathComponent
        let suffix = String(stem.prefix(8))
        return "\(project) · \(suffix)"
    }
}
