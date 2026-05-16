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
            let recent = jsonls.filter { $0.pathExtension == "jsonl" }
            guard let latest = mostRecentlyModified(recent), let mtime = modificationDate(of: latest) else { continue }
            let age = now.timeIntervalSince(mtime)
            guard age <= idleWindow else { continue }
            let lastType = lastEventType(of: latest)
            let state = classify(age: age, lastType: lastType)
            let label = projectLabel(projectDir.lastPathComponent)
            found.append(DetectedAgent(
                id: latest.lastPathComponent,
                source: .claudeCode,
                label: label,
                state: state,
                lastActivity: mtime
            ))
        }
        agents = found.sorted { $0.lastActivity > $1.lastActivity }
    }

    private func classify(age: TimeInterval, lastType: String?) -> AgentState {
        if age < activeWindow { return .active }
        if lastType == "user" || lastType == "attachment" { return .active }
        return .waitingForInput
    }

    private func mostRecentlyModified(_ urls: [URL]) -> URL? {
        urls.max { (modificationDate(of: $0) ?? .distantPast) < (modificationDate(of: $1) ?? .distantPast) }
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private func lastEventType(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let chunk: UInt64 = 4096
        let offset = size > chunk ? size - chunk : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard let last = lines.last else { return nil }
        guard let lineData = last.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let type = obj["type"] as? String
        else { return nil }
        return type
    }

    private func projectLabel(_ dirName: String) -> String {
        let raw = dirName.replacingOccurrences(of: "-Users-", with: "")
        return raw.split(separator: "-").last.map(String.init) ?? dirName
    }
}
