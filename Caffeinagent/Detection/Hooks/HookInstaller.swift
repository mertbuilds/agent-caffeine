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
        case .configMissing: return "This agent is not set up on this Mac. \(file) does not exist."
        case .unreadable: return "agent caffeine could not read \(file), so it did not change it. Check that the file is valid JSON."
        case .unexpectedShape: return "\(file) has a layout agent caffeine does not recognize, so it did not change it."
        case .changedWhileEditing: return "\(file) changed while agent caffeine was working on it. Nothing was written. Try again."
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
        case .jsonHookGroups, .jsonFlatHooks:
            guard let (keyPath, flat) = entry.format.jsonLayout else { return .unreadable }
            if isBlank(text) { return .notInstalled }
            guard let root = try? validated(text), let found = try? ourHandlers(in: root, keyPath: keyPath, flat: flat) else { return .unreadable }
            if found.isEmpty { return .notInstalled }
            let expected = expectedHandlers(for: entry, appPath: appPath)
            let same = found.count == expected.count && expected.allSatisfy(found.contains)
            return same ? .installed(version: HookCatalog.version) : .outdated
        }
    }

    // MARK: Install and uninstall

    /// The text with our entries, each at the end of its event's list, so
    /// the position of every other entry stays the same. Codex stores its
    /// trust of a hook by that position. `keeping` is for the entries of an
    /// older build that are taken out first: see `uninstalling`.
    static func installing(into text: [UInt8], entry: HookCatalogEntry, appPath: String, keeping: Set<[String]> = []) throws -> [UInt8] {
        guard let (keyPath, flat) = entry.format.jsonLayout else { return Array(HookCatalog.pluginSource(appPath: appPath).utf8) }
        if status(text: text, entry: entry, appPath: appPath) == .installed(version: HookCatalog.version) { return text }
        let cleared = try clearedForInstall(text, entry: entry, keeping: keeping)
        var source = JSONSourceText(cleared)
        let addsVersion = try lacksVersion(cleared, entry: entry)
        if addsVersion {
            source.append(to: try validated(source.bytes)) { _ in "\"\(versionKey)\": \(flatVersion)" }
        }
        for handler in expectedHandlers(for: entry, appPath: appPath) {
            var path: [String] = []
            for (index, key) in (keyPath + [handler.event]).enumerated() {
                let container = try node(at: path, in: source)
                guard container.members != nil else { throw HookInstallError.unexpectedShape }
                if try uniqueMember(key, of: container) == nil {
                    let empty = index == keyPath.count ? "[]" : "{}"
                    source.append(to: container) { _ in "\(JSONSourceText.literal(key)): \(empty)" }
                }
                path.append(key)
            }
            // Parsed again each time, because the ranges moved.
            let list = try node(at: path, in: source)
            guard list.elements != nil else { throw HookInstallError.unexpectedShape }
            let unit = source.indentUnit, ending = source.lineEnding
            source.append(to: list) { indent in group(for: handler, indent: indent, unit: unit, lineEnding: ending, flat: flat) }
        }
        // The safety net: what we wrote parses, holds our entries, and is
        // the old document again once they are taken out.
        guard status(text: source.bytes, entry: entry, appPath: appPath) == .installed(version: HookCatalog.version),
              let before = normalized(cleared, keyPath: keyPath),
              let after = normalized(try uninstalling(from: source.bytes, entry: entry, removingVersion: addsVersion), keyPath: keyPath),
              before.isEqual(after) else { throw HookInstallError.unexpectedShape }
        return source.bytes
    }

    /// The text that `installing` adds our entries to: the document
    /// without entries of an older build, `{}` for a blank file.
    static func clearedForInstall(_ text: [UInt8], entry: HookCatalogEntry, keeping: Set<[String]> = []) throws -> [UInt8] {
        try uninstalling(from: isBlank(text) ? Array("{}\n".utf8) : text, entry: entry, keeping: keeping)
    }

    static let versionKey = "version"
    static let flatVersion = 1

    /// The flat form needs a top-level `"version": 1`. True when the
    /// document has none, so that "on" adds it and "off" takes it out again.
    static func lacksVersion(_ text: [UInt8], entry: HookCatalogEntry) throws -> Bool {
        guard case .jsonFlatHooks = entry.format else { return false }
        return try uniqueMember(versionKey, of: validated(text)) == nil
    }

    /// The empty hooks object and the empty event lists of a document, by
    /// their key paths. They are the user's, and `uninstalling` is told to
    /// keep them.
    static func emptyContainers(in text: [UInt8], entry: HookCatalogEntry) -> Set<[String]> {
        guard let (keyPath, _) = entry.format.jsonLayout, !isBlank(text),
              let root = try? validated(text), let hooks = try? hooksObject(in: root, keyPath: keyPath), let members = hooks.members else { return [] }
        var found: Set<[String]> = members.isEmpty ? [keyPath] : []
        for member in members where member.value.elements?.isEmpty ?? false { found.insert(keyPath + [member.key]) }
        return found
    }

    private static func node(at path: [String], in source: JSONSourceText) throws -> JSONSourceNode {
        var current = try validated(source.bytes)
        for key in path {
            guard let next = try uniqueMember(key, of: current)?.value else { throw HookInstallError.unexpectedShape }
            current = next
        }
        return current
    }

    /// A key that is there twice is a form we do not know: a JSON reader
    /// takes one of the two, and nobody can say which.
    private static func uniqueMember(_ key: String, of node: JSONSourceNode) throws -> JSONSourceNode.Member? {
        let found = (node.members ?? []).filter { $0.key == key }
        guard found.count <= 1 else { throw HookInstallError.unexpectedShape }
        return found.first
    }

    /// The text without our entries. An event list is removed with its key
    /// only when this run took its last entry out, and so is the hooks
    /// object when this run took its last list out. A list or an object
    /// that was empty before is the user's and stays. `keeping` names the
    /// lists and the object that were empty before our entries went in
    /// (`emptyContainers`), so they stay too. `removingVersion` is for the
    /// `"version": 1` that "on" added to a flat document.
    static func uninstalling(from text: [UInt8], entry: HookCatalogEntry, keeping: Set<[String]> = [], removingVersion: Bool = false) throws -> [UInt8] {
        guard let (keyPath, flat) = entry.format.jsonLayout else { return [] }
        if isBlank(text) { return text }
        var source = JSONSourceText(text)
        var emptied: Set<String> = []
        while true {
            let root = try validated(source.bytes)
            guard let hooks = try hooksObject(in: root, keyPath: keyPath) else { break }
            guard let target = firstOurs(in: hooks, flat: flat) else { break }
            source.removeChild(at: target.index, of: target.container)
            if target.wholeGroup { emptied.insert(target.event) }
        }
        guard source.bytes != text else { return text }
        // The lists that held nothing but our entries, then the object.
        var tookList = false
        for event in emptied where !keeping.contains(keyPath + [event]) {
            let root = try validated(source.bytes)
            guard let hooks = try hooksObject(in: root, keyPath: keyPath), let members = hooks.members else { break }
            guard let index = members.firstIndex(where: { $0.key == event && ($0.value.elements?.isEmpty ?? false) }) else { continue }
            source.removeChild(at: index, of: hooks)
            tookList = true
        }
        if tookList, !keeping.contains(keyPath) {
            let root = try validated(source.bytes)
            if let hooks = try hooksObject(in: root, keyPath: keyPath), hooks.members?.isEmpty ?? false,
               let parent = try parentOfHooks(in: root, keyPath: keyPath),
               let index = parent.members?.firstIndex(where: { $0.key == keyPath.last }) {
                source.removeChild(at: index, of: parent)
            }
        }
        if removingVersion {
            let root = try validated(source.bytes)
            if let index = root.members?.firstIndex(where: { $0.key == versionKey }), let range = root.members?[index].value.range,
               String(decoding: source.bytes[range], as: UTF8.self) == String(flatVersion) {
                source.removeChild(at: index, of: root)
            }
        }
        _ = try validated(source.bytes)
        return source.bytes
    }

    // MARK: Reading

    /// `{}` and nothing else: a file with no setting in it.
    static func isEmptyDocument(_ text: [UInt8]) -> Bool {
        ((try? JSONSerialization.jsonObject(with: Data(text))) as? NSDictionary)?.count == 0
    }

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
    /// something other than an object, or that is there twice, is a form
    /// we do not know.
    private static func hooksObject(in root: JSONSourceNode, keyPath: [String]) throws -> JSONSourceNode? {
        var current = root
        for key in keyPath {
            guard let next = try uniqueMember(key, of: current)?.value else { return nil }
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
    private static func ourHandlers(in root: JSONSourceNode, keyPath: [String], flat: Bool) throws -> [OurHandler] {
        guard let hooks = try hooksObject(in: root, keyPath: keyPath) else { return [] }
        var found: [OurHandler] = []
        for member in hooks.members ?? [] {
            for group in member.value.elements ?? [] {
                if flat {
                    if isOurs(group) { found.append(OurHandler(event: member.key, matcher: nil, command: group.member("command")?.value.string ?? "")) }
                    continue
                }
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
    /// In the flat form an entry of the event list is the handler itself.
    private static func firstOurs(in hooks: JSONSourceNode, flat: Bool) -> (container: JSONSourceNode, index: Int, event: String, wholeGroup: Bool)? {
        for member in hooks.members ?? [] {
            guard let groups = member.value.elements else { continue }
            if flat {
                if let index = groups.firstIndex(where: isOurs) { return (member.value, index, member.key, true) }
                continue
            }
            for (groupIndex, group) in groups.enumerated() {
                guard let list = group.member("hooks")?.value, let handlers = list.elements,
                      let handlerIndex = handlers.firstIndex(where: isOurs) else { continue }
                if handlers.allSatisfy(isOurs) { return (member.value, groupIndex, member.key, true) }
                return (list, handlerIndex, member.key, false)
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
    static func group(for handler: OurHandler, indent: String, unit: String = "  ", lineEnding: String = "\n", flat: Bool = false) -> String {
        if flat {
            return [
                "{",
                "\(unit)\"command\": \(JSONSourceText.literal(handler.command)),",
                "\(unit)\"timeout\": \(HookCatalog.timeoutSeconds)",
                "}",
            ].joined(separator: lineEnding + indent)
        }
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
        case .jsonHookGroups, .jsonFlatHooks:
            guard let (keyPath, flat) = entry.format.jsonLayout else { return "" }
            return expectedHandlers(for: entry, appPath: appPath).map { handler in
                "\((keyPath + [handler.event]).joined(separator: ".")):\n" + group(for: handler, indent: "", flat: flat)
            }.joined(separator: "\n")
        }
    }
}

/// What the installer has to know about one agent's config from "on" to
/// "off". It is kept in our own Application Support folder, never in the
/// user's file. Without it "off" still takes out our entries, and only
/// what it emptied itself.
struct HookInstallRecord: Codable, Equatable {
    /// The key paths of the hooks object and of the event lists that were
    /// in the file and empty before our entries went in.
    var emptyBefore: [[String]] = []
    /// The config file was not there, and "on" made it. "Off" removes it
    /// again when nothing but our entries is in it.
    var createdFile = false
    /// "On" added the top-level `"version": 1` of the flat form, and "off"
    /// takes it out again. Nil in a record of an older build.
    var addedVersion: Bool?
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

    /// Next to the hook state files, and not among them: the reader of
    /// that folder removes what it does not know.
    var recordsDirectory: URL {
        home.appendingPathComponent("Library/Application Support/\(HookEvents.bundleID)/hook-installs", isDirectory: true)
    }

    private func recordURL(for entry: HookCatalogEntry) -> URL {
        recordsDirectory.appendingPathComponent("\(entry.id).json")
    }

    func record(for entry: HookCatalogEntry) -> HookInstallRecord? {
        guard let data = try? Data(contentsOf: recordURL(for: entry)) else { return nil }
        return try? JSONDecoder().decode(HookInstallRecord.self, from: data)
    }

    /// A record that cannot be written is no reason to fail: see `HookInstallRecord`.
    private func save(_ record: HookInstallRecord, for entry: HookCatalogEntry) {
        try? FileManager.default.createDirectory(at: recordsDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: recordURL(for: entry), options: .atomic)
    }

    private func forgetRecord(for entry: HookCatalogEntry) {
        try? FileManager.default.removeItem(at: recordURL(for: entry))
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
        guard entry.format.jsonLayout != nil else {
            let new = try HookConfigEditor.installing(into: old ?? [], entry: entry, appPath: appPath)
            return try write(new, to: url, replacing: old, backup: false)
        }
        let keeping = Set(record(for: entry)?.emptyBefore ?? [])
        let new = try HookConfigEditor.installing(into: old ?? [], entry: entry, appPath: appPath, keeping: keeping)
        // Already there: the record of the first time stands.
        guard new != old else { return }
        let cleared = try HookConfigEditor.clearedForInstall(old ?? [], entry: entry, keeping: keeping)
        let empty = HookConfigEditor.emptyContainers(in: cleared, entry: entry)
        try write(new, to: url, replacing: old, backup: true)
        let created = old == nil || (record(for: entry)?.createdFile ?? false)
        let addedVersion = try HookConfigEditor.lacksVersion(cleared, entry: entry) || (record(for: entry)?.addedVersion ?? false)
        save(HookInstallRecord(emptyBefore: empty.sorted { $0.lexicographicallyPrecedes($1) }, createdFile: created, addedVersion: addedVersion ? true : nil), for: entry)
    }

    func uninstall(_ entry: HookCatalogEntry) throws {
        let url = configURL(for: entry)
        guard let old = try read(url) else { return }
        switch entry.format {
        case .pluginFile:
            guard HookConfigEditor.status(text: old, entry: entry, appPath: appPath) != .unreadable else { throw HookInstallError.notOurFile }
            guard (try? FileManager.default.removeItem(at: url)) != nil else { throw HookInstallError.writeFailed }
        case .jsonHookGroups, .jsonFlatHooks:
            let known = record(for: entry)
            let new = try HookConfigEditor.uninstalling(
                from: old, entry: entry, keeping: Set(known?.emptyBefore ?? []), removingVersion: known?.addedVersion == true
            )
            if known?.createdFile == true, new != old, HookConfigEditor.isEmptyDocument(new) {
                try remove(url, holding: old)
            } else {
                try write(new, to: url, replacing: old, backup: true)
            }
            forgetRecord(for: entry)
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

    /// Removes a file that we made and that holds nothing any more. The
    /// backup is written first and stays. A link is the user's: the file
    /// behind it is emptied, not removed.
    private func remove(_ url: URL, holding old: [UInt8]) throws {
        let target = url.resolvingSymlinksInPath()
        guard target.path == url.standardizedFileURL.path else {
            return try write(Array("{}\n".utf8), to: url, replacing: old, backup: true)
        }
        guard try read(url) == old else { throw HookInstallError.changedWhileEditing }
        do {
            try Data(old).write(to: backupURL(for: target), options: .atomic)
            pruneBackups(of: target)
            try FileManager.default.removeItem(at: target)
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
