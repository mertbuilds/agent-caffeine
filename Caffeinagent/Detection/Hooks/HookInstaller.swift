import Foundation

enum HookStatus: Equatable {
    case notInstalled
    case installed(version: Int)
    /// Our entries are there, from an older build or with another app path.
    case outdated
    /// The agent's config folder is not there: the agent is not set up.
    case configMissing
    /// The file is there and cannot be read or understood. It is never rewritten.
    case unreadable
}

enum HookInstallError: Error, Equatable {
    case configMissing
    case unreadable
    case unexpectedShape
    case changedWhileEditing
    case notOurFile
    case writeFailed

    /// One plain line for Preferences. `file` is the path as the user knows it.
    func message(file: String) -> String {
        switch self {
        case .configMissing: return "This agent is not set up on this Mac. \(file) is not there."
        case .unreadable: return "agent caffeine could not read \(file), so it did not change it. Check that the file is valid JSON."
        case .unexpectedShape: return "\(file) has a form agent caffeine does not know, so it did not change it."
        case .changedWhileEditing: return "\(file) changed while agent caffeine worked on it. Nothing was written. Try again."
        case .notOurFile: return "\(file) was not written by agent caffeine, so it did not change it."
        case .writeFailed: return "agent caffeine could not write \(file). Nothing was changed."
        }
    }
}

/// The pure part: the text of a config in, the text with or without our
/// entries out. It never touches an entry of another tool.
enum HookConfigEditor {
    struct OurHandler: Equatable {
        var event: String
        var matcher: String?
        var command: String
    }

    static func expectedHandlers(for entry: HookCatalogEntry, appPath: String) -> [OurHandler] {
        entry.rules.map { OurHandler(event: $0.event, matcher: $0.matcher, command: HookCatalog.command(agent: entry.id, event: $0.event, appPath: appPath)) }
    }

    // MARK: Status

    static func status(text: [UInt8], entry: HookCatalogEntry, appPath: String) -> HookStatus {
        switch entry.format {
        case .pluginFile:
            let source = String(decoding: text, as: UTF8.self)
            if source == HookCatalog.pluginSource(appPath: appPath) { return .installed(version: HookCatalog.version) }
            return source.contains(HookCatalog.pluginMarker) ? .outdated : .unreadable
        case .jsonHookGroups(let keyPath):
            if isBlank(text) { return .notInstalled }
            guard let root = try? validated(text), let found = try? ourHandlers(in: root, keyPath: keyPath) else { return .unreadable }
            if found.isEmpty { return .notInstalled }
            let expected = expectedHandlers(for: entry, appPath: appPath)
            let same = found.count == expected.count && expected.allSatisfy(found.contains)
            return same ? .installed(version: HookCatalog.version) : .outdated
        }
    }

    // MARK: Install and uninstall

    /// The text with our entries, each at the end of its event's list, so
    /// the position of every other entry stays the same. Codex stores its
    /// trust of a hook by that position.
    static func installing(into text: [UInt8], entry: HookCatalogEntry, appPath: String) throws -> [UInt8] {
        guard case .jsonHookGroups(let keyPath) = entry.format else { return Array(HookCatalog.pluginSource(appPath: appPath).utf8) }
        if status(text: text, entry: entry, appPath: appPath) == .installed(version: HookCatalog.version) { return text }
        let original = isBlank(text) ? Array("{}\n".utf8) : text
        let cleared = try uninstalling(from: original, entry: entry)
        var source = JSONSourceText(cleared)
        for handler in expectedHandlers(for: entry, appPath: appPath) {
            var path: [String] = []
            for (index, key) in (keyPath + [handler.event]).enumerated() {
                let container = try node(at: path, in: source)
                guard container.members != nil else { throw HookInstallError.unexpectedShape }
                if container.member(key) == nil {
                    let empty = index == keyPath.count ? "[]" : "{}"
                    source.append(to: container) { _ in "\(JSONSourceText.literal(key)): \(empty)" }
                }
                path.append(key)
            }
            // Parsed again each time, because the ranges moved.
            let list = try node(at: path, in: source)
            guard list.elements != nil else { throw HookInstallError.unexpectedShape }
            let unit = source.indentUnit, ending = source.lineEnding
            source.append(to: list) { indent in group(for: handler, indent: indent, unit: unit, lineEnding: ending) }
        }
        // The safety net: what we wrote parses, holds our entries, and is
        // the old document again once they are taken out.
        guard status(text: source.bytes, entry: entry, appPath: appPath) == .installed(version: HookCatalog.version),
              let before = normalized(cleared, keyPath: keyPath),
              let after = normalized(try uninstalling(from: source.bytes, entry: entry), keyPath: keyPath),
              before.isEqual(after) else { throw HookInstallError.unexpectedShape }
        return source.bytes
    }

    private static func node(at path: [String], in source: JSONSourceText) throws -> JSONSourceNode {
        var current = try validated(source.bytes)
        for key in path {
            guard let next = current.member(key)?.value else { throw HookInstallError.unexpectedShape }
            current = next
        }
        return current
    }

    /// The text without our entries. An event list that we empty is removed
    /// with its key, and so is the hooks object when nothing is left in it.
    static func uninstalling(from text: [UInt8], entry: HookCatalogEntry) throws -> [UInt8] {
        guard case .jsonHookGroups(let keyPath) = entry.format else { return [] }
        if isBlank(text) { return text }
        var source = JSONSourceText(text)
        var emptied = false
        while true {
            let root = try validated(source.bytes)
            guard let hooks = try hooksObject(in: root, keyPath: keyPath) else { break }
            guard let target = firstOurs(in: hooks) else { break }
            source.removeChild(at: target.index, of: target.container)
            emptied = true
        }
        guard emptied else { return text }
        // Lists and objects that held nothing but our entries.
        while true {
            let root = try validated(source.bytes)
            guard let hooks = try hooksObject(in: root, keyPath: keyPath), let members = hooks.members else { break }
            if let index = members.firstIndex(where: { $0.value.elements?.isEmpty ?? false }) {
                source.removeChild(at: index, of: hooks)
            } else if members.isEmpty, let parent = try parentOfHooks(in: root, keyPath: keyPath),
                      let index = parent.members?.firstIndex(where: { $0.key == keyPath.last }) {
                source.removeChild(at: index, of: parent)
                break
            } else {
                break
            }
        }
        _ = try validated(source.bytes)
        return source.bytes
    }

    // MARK: Reading

    static func isBlank(_ text: [UInt8]) -> Bool {
        text.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0a || $0 == 0x0d }
    }

    /// Both parsers have to accept the text.
    private static func validated(_ text: [UInt8]) throws -> JSONSourceNode {
        guard (try? JSONSerialization.jsonObject(with: Data(text))) is NSDictionary, let root = try? JSONSourceParser.parse(text), root.members != nil else {
            throw HookInstallError.unreadable
        }
        return root
    }

    /// Nil when the key path is not there. A key on the path that holds
    /// something other than an object is a form we do not know.
    private static func hooksObject(in root: JSONSourceNode, keyPath: [String]) throws -> JSONSourceNode? {
        var current = root
        for key in keyPath {
            guard let next = current.member(key)?.value else { return nil }
            guard next.members != nil else { throw HookInstallError.unexpectedShape }
            current = next
        }
        return current
    }

    private static func parentOfHooks(in root: JSONSourceNode, keyPath: [String]) throws -> JSONSourceNode? {
        try hooksObject(in: root, keyPath: Array(keyPath.dropLast()))
    }

    private static func isOurs(_ handler: JSONSourceNode) -> Bool {
        handler.member("command")?.value.string?.contains(HookCatalog.marker) ?? false
    }

    /// Other tools keep things in the hooks object that are no event lists
    /// (Droid: `claudeHooksImported`), and those are passed over.
    private static func ourHandlers(in root: JSONSourceNode, keyPath: [String]) throws -> [OurHandler] {
        guard let hooks = try hooksObject(in: root, keyPath: keyPath) else { return [] }
        var found: [OurHandler] = []
        for member in hooks.members ?? [] {
            for group in member.value.elements ?? [] {
                for handler in group.member("hooks")?.value.elements ?? [] where isOurs(handler) {
                    found.append(OurHandler(
                        event: member.key, matcher: group.member("matcher")?.value.string,
                        command: handler.member("command")?.value.string ?? ""
                    ))
                }
            }
        }
        return found
    }

    /// The first thing to remove: a whole group when all its handlers are
    /// ours, else the one handler inside a group that another tool shares.
    private static func firstOurs(in hooks: JSONSourceNode) -> (container: JSONSourceNode, index: Int)? {
        for member in hooks.members ?? [] {
            guard let groups = member.value.elements else { continue }
            for (groupIndex, group) in groups.enumerated() {
                guard let list = group.member("hooks")?.value, let handlers = list.elements,
                      let handlerIndex = handlers.firstIndex(where: isOurs) else { continue }
                if handlers.allSatisfy(isOurs) { return (member.value, groupIndex) }
                return (list, handlerIndex)
            }
        }
        return nil
    }

    /// The document as Foundation reads it, without empty lists and objects
    /// under the hooks key, for the comparison of before and after.
    private static func normalized(_ text: [UInt8], keyPath: [String]) -> NSDictionary? {
        guard let root = (try? JSONSerialization.jsonObject(with: Data(text), options: [.mutableContainers])) as? NSMutableDictionary else { return nil }
        var chain: [NSMutableDictionary] = [root]
        for key in keyPath {
            guard let next = chain.last?[key] as? NSMutableDictionary else { return root }
            chain.append(next)
        }
        if let hooks = chain.last {
            let empty = hooks.allKeys.filter { (hooks[$0] as? NSArray)?.count == 0 }
            hooks.removeObjects(forKeys: empty)
        }
        for (index, key) in keyPath.enumerated().reversed() where chain[index + 1].count == 0 {
            chain[index].removeObject(forKey: key)
        }
        return root
    }

    // MARK: Writing

    /// The source of one group, as it is shown in Preferences and written
    /// into the file.
    static func group(for handler: OurHandler, indent: String, unit: String = "  ", lineEnding: String = "\n") -> String {
        var lines = ["{"]
        if let matcher = handler.matcher { lines.append("\(unit)\"matcher\": \(JSONSourceText.literal(matcher)),") }
        lines += [
            "\(unit)\"hooks\": [",
            "\(unit)\(unit){",
            "\(unit)\(unit)\(unit)\"type\": \"command\",",
            "\(unit)\(unit)\(unit)\"command\": \(JSONSourceText.literal(handler.command)),",
            "\(unit)\(unit)\(unit)\"timeout\": \(HookCatalog.timeoutSeconds)",
            "\(unit)\(unit)}",
            "\(unit)]",
            "}",
        ]
        return lines.joined(separator: lineEnding + indent)
    }

    /// What turning the hooks on adds, for the "Show what changes" view.
    static func preview(for entry: HookCatalogEntry, appPath: String) -> String {
        switch entry.format {
        case .pluginFile:
            return HookCatalog.pluginSource(appPath: appPath)
        case .jsonHookGroups(let keyPath):
            return expectedHandlers(for: entry, appPath: appPath).map { handler in
                "\((keyPath + [handler.event]).joined(separator: ".")):\n" + group(for: handler, indent: "")
            }.joined(separator: "\n")
        }
    }
}

/// The thin shell around `HookConfigEditor`: it reads the file, writes a
/// backup next to it, and replaces the file in one step.
struct HookInstaller {
    static let backupInfix = ".agent-caffeine-backup-"
    static let backupsKept = 3

    var home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    var appPath = HookCatalog.stableAppPath
    var now: () -> Date = Date.init

    func configURL(for entry: HookCatalogEntry) -> URL {
        home.appendingPathComponent(entry.configPath)
    }

    /// The path with `~`, as it is shown.
    func displayPath(for entry: HookCatalogEntry) -> String {
        "~/" + entry.configPath
    }

    /// The folder that shows the agent is set up: `~/.claude`, `~/.codex`,
    /// `~/.factory`, `~/.config/opencode`.
    private func agentFolder(for entry: HookCatalogEntry) -> URL {
        let parts = entry.configPath.split(separator: "/").map(String.init)
        let depth = parts.first == ".config" ? 2 : 1
        return parts.prefix(depth).reduce(home) { $0.appendingPathComponent($1) }
    }

    private func agentIsSetUp(_ entry: HookCatalogEntry) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: agentFolder(for: entry).path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Nil when the file is not there.
    private func read(_ url: URL) throws -> [UInt8]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { throw HookInstallError.unreadable }
        return Array(data)
    }

    func status(of entry: HookCatalogEntry) -> HookStatus {
        guard agentIsSetUp(entry) else { return .configMissing }
        guard let text = try? read(configURL(for: entry)) else {
            return FileManager.default.fileExists(atPath: configURL(for: entry).path) ? .unreadable : .notInstalled
        }
        return HookConfigEditor.status(text: text, entry: entry, appPath: appPath)
    }

    func install(_ entry: HookCatalogEntry) throws {
        guard agentIsSetUp(entry) else { throw HookInstallError.configMissing }
        let url = configURL(for: entry)
        let old = try read(url)
        if case .pluginFile = entry.format, let old, !old.isEmpty, HookConfigEditor.status(text: old, entry: entry, appPath: appPath) == .unreadable {
            throw HookInstallError.notOurFile
        }
        let new = try HookConfigEditor.installing(into: old ?? [], entry: entry, appPath: appPath)
        try write(new, to: url, replacing: old, backup: entry.format != .pluginFile)
    }

    func uninstall(_ entry: HookCatalogEntry) throws {
        let url = configURL(for: entry)
        guard let old = try read(url) else { return }
        switch entry.format {
        case .pluginFile:
            guard HookConfigEditor.status(text: old, entry: entry, appPath: appPath) != .unreadable else { throw HookInstallError.notOurFile }
            guard (try? FileManager.default.removeItem(at: url)) != nil else { throw HookInstallError.writeFailed }
        case .jsonHookGroups:
            let new = try HookConfigEditor.uninstalling(from: old, entry: entry)
            try write(new, to: url, replacing: old, backup: true)
        }
    }

    /// Nothing is written when the text is the same. The file is replaced
    /// by a rename, a link is followed so that it stays a link, and the
    /// file keeps its permissions.
    private func write(_ new: [UInt8], to url: URL, replacing old: [UInt8]?, backup: Bool) throws {
        guard new != old else { return }
        let target = url.resolvingSymlinksInPath()
        let manager = FileManager.default
        guard try read(url) == old else { throw HookInstallError.changedWhileEditing }
        do {
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let permissions = (try? manager.attributesOfItem(atPath: target.path))?[.posixPermissions]
            if backup, let old {
                let copy = backupURL(for: target)
                try Data(old).write(to: copy, options: .atomic)
                if let permissions { try? manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: copy.path) }
                pruneBackups(of: target)
            }
            try Data(new).write(to: target, options: .atomic)
            if let permissions { try? manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path) }
        } catch {
            throw HookInstallError.writeFailed
        }
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    /// Two changes within one second get two backups.
    func backupURL(for file: URL) -> URL {
        let base = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + Self.backupInfix + Self.stamp.string(from: now()))
        var url = base
        var count = 1
        while FileManager.default.fileExists(atPath: url.path) {
            count += 1
            url = URL(fileURLWithPath: base.path + "-\(count)")
        }
        return url
    }

    /// The names sort by time, so the last ones are the newest.
    private func pruneBackups(of file: URL) {
        let folder = file.deletingLastPathComponent()
        let prefix = file.lastPathComponent + Self.backupInfix
        let backups = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasPrefix(prefix) }.sorted()
        for name in backups.dropLast(Self.backupsKept) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}
