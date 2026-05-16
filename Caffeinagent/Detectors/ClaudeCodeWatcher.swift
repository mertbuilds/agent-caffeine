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
                let parsed = parseTail(of: url)
                let state = classify(age: age, lastType: parsed.lastType)
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

    private func classify(age: TimeInterval, lastType: String?) -> AgentState {
        if age < activeWindow { return .active }
        if lastType == "user" || lastType == "attachment" { return .active }
        return .waitingForInput
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private struct TailParse {
        var lastType: String?
        var title: String?
    }

    /// Reads up to the last ~16KB of a jsonl and pulls out the most recent
    /// `type` field plus the most recent `ai-title` if either is present.
    private func parseTail(of url: URL) -> TailParse {
        var result = TailParse()
        guard let handle = try? FileHandle(forReadingFrom: url) else { return result }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return result }
        let chunk: UInt64 = 16384
        let offset = size > chunk ? size - chunk : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return result }
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines.reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            if result.lastType == nil, let t = obj["type"] as? String { result.lastType = t }
            if result.title == nil, obj["type"] as? String == "ai-title", let t = obj["aiTitle"] as? String { result.title = t }
            if result.lastType != nil && result.title != nil { break }
        }
        return result
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
