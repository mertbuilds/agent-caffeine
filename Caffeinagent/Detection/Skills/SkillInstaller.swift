import CryptoKit
import Darwin
import Foundation
import os

/// The skill as one agent has it.
enum SkillAgentStatus: Equatable {
    case notInstalled
    /// Our skill of this build, or of a newer one, is in a folder the
    /// agent reads. `place` is relative to the home folder.
    case installed(place: String)
    /// Our skill of an older build is there.
    case outdated(place: String)
    /// A skill of the same name is there and is not ours. It is left as
    /// it is, and the agent reads that one.
    case foreign(place: String)
}

/// What is at `~/.local/bin/agent-caffeine`.
enum SkillLinkState: Equatable {
    case none
    /// A link to the tool inside a copy of the app that is there.
    case ours(target: String)
    /// A link to the tool inside a copy of the app that is gone. It is
    /// replaced.
    case dead
    /// A file, a folder or a link to something else, also to something
    /// that is gone, for example on a drive that is not plugged in. It is
    /// never changed.
    case foreign
}

enum SkillInstallError: Error, Equatable {
    case notOurs
    case linkedOutside
    case notAFolder
    case writeFailed
    case noTool
    case linkNotOurs
    case notInApplications

    /// One plain line for Settings.
    /// - Parameter place: the skills folder, relative to the home folder.
    func message(place: String) -> String {
        let folder = "~/\(place)/\(SkillCatalog.skillName)"
        let root = "~/" + (place as NSString).deletingLastPathComponent
        switch self {
        case .notOurs: return "\(folder) was not made by Agent Caffeine, so it did not change it."
        case .linkedOutside: return "~/\(place) is a link to a folder outside \(root), so Agent Caffeine did not write there."
        case .notAFolder: return "~/\(place) is not a folder, so Agent Caffeine did not write there."
        case .writeFailed: return "Agent Caffeine could not write \(folder). Nothing was changed."
        case .noTool, .linkNotOurs, .notInApplications: return linkMessage
        }
    }

    /// The same for the link to the tool.
    var linkMessage: String {
        let link = "~/" + SkillInstaller.linkPath
        switch self {
        case .linkNotOurs, .notOurs: return "\(link) was not made by Agent Caffeine, so it did not change it."
        case .noTool: return "The command line tool is not in this copy of Agent Caffeine, so no link was made."
        case .notInApplications: return PanelText.commandLinkNeedsApplications
        case .linkedOutside, .notAFolder, .writeFailed: return "Agent Caffeine could not make the link \(link). Nothing was changed."
        }
    }
}

/// What the installer has to know from "Set up for agents" to "Remove":
/// the folders it made, so they go again when they are empty, and the
/// text it wrote, so a file the user edited is not replaced at launch
/// and not taken out by "Remove".
/// It is kept in our own Application Support folder. Without it "Remove"
/// still takes out our files and our link, and leaves the folders.
struct SkillInstallRecord: Codable, Equatable {
    struct Place: Codable, Equatable {
        /// The folders "on" made, relative to the home folder.
        var created: [String] = []
        /// SHA-256 of the file as it was written.
        var digest: String
        var version: Int
    }

    struct Link: Codable, Equatable {
        var created: [String] = []
        var target: String
    }

    /// By skills folder, relative to the home folder.
    var places: [String: Place] = [:]
    var link: Link?

    var isEmpty: Bool { places.isEmpty && link == nil }
}

/// What Settings and the setup window show.
struct SkillSnapshot: Equatable {
    struct Agent: Equatable, Identifiable {
        let entry: SkillCatalogEntry
        var status: SkillAgentStatus
        var id: String { entry.id }
    }

    /// The agents that are set up on this Mac.
    var agents: [Agent] = []
    var link: SkillLinkState = .none
    /// False when the app does not run from the Applications folder. The
    /// link is not offered then: see `SkillInstaller.link`.
    var linkAllowed = true
    /// The skills folders "Set up for agents" would write to now,
    /// relative to the home folder.
    var planned: [String] = []
}

/// Writes the skill of the command line tool into the skills folders of
/// the agents on this Mac, and links the tool into `~/.local/bin`. It
/// writes one folder of its own per place, `agent-caffeine`, and one
/// link, and nothing else. It never follows a link out of an agent's
/// folder, and never changes a folder, a file or a link it did not make.
struct SkillInstaller {
    static let linkPath = ".local/bin/" + CommandLineSetup.toolName
    /// Agent ids are the other keys of the errors of `setUp`.
    static let linkKey = "link"

    var home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    /// The bundled skill, without our line.
    var skill: String
    /// The tool in the copy of the app that runs.
    var toolPath: String
    /// The tool in the copy in the Applications folder, where the link
    /// belongs.
    var stableToolPath = CommandLineSetup(appPath: HookCatalog.stableAppPath).toolPath

    private static let log = Logger(subsystem: "com.caffeinagent.app", category: "Skills")

    // MARK: Paths

    /// Next to `hook-installs`.
    var recordURL: URL {
        home.appendingPathComponent("Library/Application Support/\(HookEvents.bundleID)/skill-installs/record.json")
    }

    var linkURL: URL { home.appendingPathComponent(Self.linkPath) }

    func fileURL(in place: String) -> URL {
        folderURL(in: place).appendingPathComponent(SkillCatalog.fileName)
    }

    private func folderURL(in place: String) -> URL {
        home.appendingPathComponent(place).appendingPathComponent(SkillCatalog.skillName)
    }

    private var installedText: String? { SkillCatalog.installedText(of: skill) }

    /// A debug build, a copy in Downloads and a disk image move away or
    /// go, so the link is offered only from the Applications folder.
    var isInApplications: Bool { toolPath == stableToolPath }

    // MARK: What is there

    private enum Kind { case missing, link, folder, file }

    /// The thing itself: a link is not followed.
    private func kind(_ url: URL) -> Kind {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return .missing }
        switch info.st_mode & S_IFMT {
        case S_IFLNK: return .link
        case S_IFDIR: return .folder
        default: return .file
        }
    }

    private func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private enum PlaceState: Equatable {
        case none
        case ours(version: Int)
        case foreign
    }

    /// Ours is a plain file `SKILL.md` with our line, in a plain folder.
    /// Anything else of that name is someone else's.
    private func state(of place: String) -> PlaceState {
        switch kind(folderURL(in: place)) {
        case .missing: return .none
        case .link, .file: return .foreign
        case .folder:
            guard kind(fileURL(in: place)) == .file, let text = try? String(contentsOf: fileURL(in: place), encoding: .utf8),
                  let version = SkillCatalog.version(ofInstalled: text) else { return .foreign }
            return .ours(version: version)
        }
    }

    func isFound(_ entry: SkillCatalogEntry) -> Bool {
        isFolder(home.appendingPathComponent(entry.homeFolder))
    }

    func status(of entry: SkillCatalogEntry) -> SkillAgentStatus {
        var outdated: String?, foreign: String?
        for place in entry.places {
            switch state(of: place) {
            case .ours(let version) where version >= SkillCatalog.version: return .installed(place: place)
            case .ours: outdated = outdated ?? place
            case .foreign: foreign = foreign ?? place
            case .none: break
            }
        }
        if let outdated { return .outdated(place: outdated) }
        if let foreign { return .foreign(place: foreign) }
        return .notInstalled
    }

    func linkState() -> SkillLinkState {
        switch kind(linkURL) {
        case .missing: return .none
        case .file, .folder: return .foreign
        case .link:
            guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path) else { return .foreign }
            guard target.hasSuffix(CommandLineSetup.pathInApp) else { return .foreign }
            return FileManager.default.fileExists(atPath: linkURL.path) ? .ours(target: target) : .dead
        }
    }

    /// What "Set up for agents" writes: one folder per agent that has the
    /// skill nowhere yet. An agent that reads a folder another agent got
    /// the skill in needs none of its own, and two copies would show the
    /// skill twice in some agents. So the agents with one folder come
    /// first.
    private func plan() -> [(entry: SkillCatalogEntry, place: String)] {
        let found = SkillCatalog.entries.filter(isFound)
        var covered = Set(SkillCatalog.places.filter {
            if case .ours(let version) = state(of: $0) { return version >= SkillCatalog.version }
            return false
        })
        var writes: [(SkillCatalogEntry, String)] = []
        for entry in found.filter({ $0.places.count == 1 }) + found.filter({ $0.places.count > 1 }) {
            guard !entry.places.contains(where: covered.contains) else { continue }
            let place: String
            switch status(of: entry) {
            case .installed, .foreign: continue
            case .outdated(let old): place = old
            case .notInstalled: place = entry.places[0]
            }
            writes.append((entry, place))
            covered.insert(place)
        }
        return writes
    }

    func snapshot() -> SkillSnapshot {
        SkillSnapshot(
            agents: SkillCatalog.entries.filter(isFound).map { SkillSnapshot.Agent(entry: $0, status: status(of: $0)) },
            link: linkState(),
            linkAllowed: isInApplications,
            planned: plan().map(\.place)
        )
    }

    // MARK: The record

    func record() -> SkillInstallRecord {
        guard let data = try? Data(contentsOf: recordURL), let record = try? JSONDecoder().decode(SkillInstallRecord.self, from: data) else {
            return SkillInstallRecord()
        }
        return record
    }

    /// A record that cannot be written is no reason to fail: see `SkillInstallRecord`.
    private func save(_ record: SkillInstallRecord) {
        let folder = recordURL.deletingLastPathComponent()
        guard !record.isEmpty else {
            try? FileManager.default.removeItem(at: recordURL)
            rmdir(folder.path)
            return
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(record) else { return }
        try? data.write(to: recordURL, options: .atomic)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Folders

    /// Makes the folders of `path` below the home folder that are not
    /// there, one by one, and gives the ones it made. A link on the way is
    /// followed when it leads to a folder.
    private func makeFolders(_ path: String) throws -> [String] {
        var made: [String] = []
        var current = ""
        do {
            for part in path.split(separator: "/") {
                current += (current.isEmpty ? "" : "/") + part
                let url = home.appendingPathComponent(current)
                if kind(url) == .missing {
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                    made.append(current)
                } else if !isFolder(url) {
                    throw SkillInstallError.notAFolder
                }
            }
        } catch {
            removeFolders(made)
            throw error as? SkillInstallError ?? .writeFailed
        }
        return made
    }

    /// Removes the folders that are empty, the deepest first. `rmdir`
    /// leaves a folder that holds anything.
    private func removeFolders(_ paths: [String]) {
        for path in paths.sorted(by: { $0.count > $1.count }) {
            rmdir(home.appendingPathComponent(path).path)
        }
    }

    /// The folders of a record that are ours to remove: only folders on
    /// the way to `path`. A record that names anything else is not believed.
    private func believed(_ created: [String], onTheWayTo path: String) -> [String] {
        created.filter { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// Refuses a skills folder that is a link out of the folder above it:
    /// `~/.claude/skills` has to be inside `~/.claude`. The folder above
    /// may itself be a link, which is where the user keeps that agent.
    private func checkContainment(of place: String) throws {
        let skills = home.appendingPathComponent(place)
        let root = skills.deletingLastPathComponent()
        switch kind(skills) {
        case .missing, .folder: return
        case .file: throw SkillInstallError.notAFolder
        case .link:
            let inside = root.resolvingSymlinksInPath().path + "/"
            guard skills.resolvingSymlinksInPath().path.hasPrefix(inside) else { throw SkillInstallError.linkedOutside }
            guard isFolder(skills) else { throw SkillInstallError.notAFolder }
        }
    }

    // MARK: Install

    /// Writes `<place>/agent-caffeine/SKILL.md`. A file of ours that is
    /// there is replaced. A folder or a file of that name that is not
    /// ours is refused.
    func install(place: String) throws {
        guard let text = installedText else { throw SkillInstallError.writeFailed }
        try checkContainment(of: place)
        let state = state(of: place)
        guard state != .foreign else { throw SkillInstallError.notOurs }
        let data = Data(text.utf8)
        let file = fileURL(in: place)
        var record = record()
        if state != .none, (try? Data(contentsOf: file)) == data {
            // Already there to the letter: only the record may be missing.
            if record.places[place] == nil {
                record.places[place] = SkillInstallRecord.Place(digest: Self.digest(data), version: SkillCatalog.version)
                save(record)
            }
            return
        }
        let made = try makeFolders(place + "/" + SkillCatalog.skillName)
        do {
            try data.write(to: file, options: .atomic)
        } catch {
            removeFolders(made)
            throw SkillInstallError.writeFailed
        }
        let earlier = state == .none ? [] : record.places[place]?.created ?? []
        record.places[place] = SkillInstallRecord.Place(
            created: (earlier + made.filter { !earlier.contains($0) }).sorted(), digest: Self.digest(data), version: SkillCatalog.version
        )
        save(record)
    }

    /// "Install" and "Update" next to one agent.
    func install(for entry: SkillCatalogEntry) throws {
        switch status(of: entry) {
        case .installed: return
        case .outdated(let place): try install(place: place)
        case .foreign: throw SkillInstallError.notOurs
        case .notInstalled: try install(place: entry.places[0])
        }
    }

    /// Makes `~/.local/bin/agent-caffeine` a link to the tool. A link of
    /// ours to a copy that is gone is replaced. A link of ours to another
    /// copy that is there is moved only by the copy in the Applications
    /// folder. A file, a folder and a link to something else are refused.
    func link() throws {
        guard FileManager.default.isExecutableFile(atPath: toolPath) else { throw SkillInstallError.noTool }
        var record = record()
        var made: [String] = []
        switch linkState() {
        case .foreign: throw SkillInstallError.linkNotOurs
        case .ours(let target) where target == toolPath:
            if record.link == nil {
                record.link = SkillInstallRecord.Link(target: toolPath)
                save(record)
            }
            return
        case .ours:
            guard isInApplications else { throw SkillInstallError.notInApplications }
            guard unlink(linkURL.path) == 0 else { throw SkillInstallError.writeFailed }
        case .dead:
            guard unlink(linkURL.path) == 0 else { throw SkillInstallError.writeFailed }
        case .none:
            made = try makeFolders((Self.linkPath as NSString).deletingLastPathComponent)
        }
        do {
            try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: toolPath)
        } catch {
            removeFolders(made)
            throw SkillInstallError.writeFailed
        }
        let earlier = record.link?.created ?? []
        record.link = SkillInstallRecord.Link(created: (earlier + made.filter { !earlier.contains($0) }).sorted(), target: toolPath)
        save(record)
    }

    /// "Set up for agents": the skill for every agent on this Mac that has
    /// it nowhere, and the link when the app runs from the Applications
    /// folder. Gives what went wrong in plain words, by
    /// agent id and `linkKey`. One place that fails does not stop the rest.
    @discardableResult
    func setUp() -> [String: String] {
        var errors: [String: String] = [:]
        for (entry, place) in plan() {
            do {
                try install(place: place)
            } catch {
                errors[entry.id] = (error as? SkillInstallError ?? .writeFailed).message(place: place)
            }
        }
        // A folder that was refused and is a link to a folder another
        // agent got the skill in: the agent reads it there.
        for entry in SkillCatalog.entries where errors[entry.id] != nil {
            if case .installed = status(of: entry) { errors[entry.id] = nil }
        }
        guard isInApplications else { return errors }
        do {
            try link()
        } catch {
            errors[Self.linkKey] = (error as? SkillInstallError ?? .writeFailed).linkMessage
        }
        return errors
    }

    // MARK: Remove

    /// Takes our file out of one place, then our folder and the folders
    /// the record says we made, each only when it is empty. A file that
    /// is no longer what the record says we wrote was edited: it stays,
    /// with its record, and the answer is false.
    private func remove(place: String, record: inout SkillInstallRecord) throws -> Bool {
        let folder = place + "/" + SkillCatalog.skillName
        let created = believed(record.places[place]?.created ?? [], onTheWayTo: folder)
        // Seen through a link that leads out of the agent's folder: the
        // file is removed where it is, by the place it belongs to.
        if case .ours = state(of: place), (try? checkContainment(of: place)) != nil {
            if let known = record.places[place], let data = try? Data(contentsOf: fileURL(in: place)), Self.digest(data) != known.digest {
                return false
            }
            guard unlink(fileURL(in: place).path) == 0 else { throw SkillInstallError.writeFailed }
            removeFolders([folder] + created)
        } else if state(of: place) == .none {
            // The user took the skill out by hand: our empty folders go too.
            removeFolders(created)
        }
        record.places[place] = nil
        return true
    }

    /// "Remove": every file, link and empty folder the app made, and
    /// nothing else. Gives what was not removed and why, by place and
    /// `linkKey`.
    @discardableResult
    func removeAll() -> [String: String] {
        var errors: [String: String] = [:]
        var record = record()
        var places = SkillCatalog.places
        places += record.places.keys.sorted().filter { !places.contains($0) }
        for place in places {
            do {
                if try !remove(place: place, record: &record) {
                    errors[place] = "~/\(place)/\(SkillCatalog.skillName)/\(SkillCatalog.fileName) was edited, so it was left."
                }
            } catch {
                errors[place] = "Agent Caffeine could not remove ~/\(place)/\(SkillCatalog.skillName)/\(SkillCatalog.fileName)."
            }
        }
        switch linkState() {
        case .ours, .dead:
            if unlink(linkURL.path) == 0 {
                let folder = (Self.linkPath as NSString).deletingLastPathComponent
                removeFolders(believed(record.link?.created ?? [], onTheWayTo: folder))
            } else {
                errors[Self.linkKey] = "Agent Caffeine could not remove ~/\(Self.linkPath)."
            }
        case .none, .foreign: break
        }
        record.link = nil
        save(record)
        return errors
    }

    // MARK: At launch

    /// Brings what is already installed up to this build, with no word of
    /// the user: a file of ours from an older build, only while it is to
    /// the letter what that build wrote, and the link: one the record
    /// says the app made, when it points at another copy, and one to a
    /// copy that is gone. A link the user made by hand to another copy,
    /// for example to a build of their own, stays. Nothing new is installed here. A file
    /// the user edited stays, and Settings offers "Update" for it.
    @discardableResult
    func updateOwn() -> [String] {
        var updated: [String] = []
        for (place, known) in record().places.sorted(by: { $0.key < $1.key }) {
            guard case .ours(let version) = state(of: place), version < SkillCatalog.version,
                  let data = try? Data(contentsOf: fileURL(in: place)), Self.digest(data) == known.digest,
                  (try? install(place: place)) != nil else { continue }
            Self.log.notice("updated the skill in \(place, privacy: .public) from v=\(version) to v=\(SkillCatalog.version)")
            updated.append(place)
        }
        let moves: Bool
        switch linkState() {
        case .ours(let target): moves = target != toolPath && record().link != nil
        case .dead: moves = true
        case .none, .foreign: moves = false
        }
        if moves, (try? link()) != nil {
            Self.log.notice("the link to the command line tool points at this copy of the app now")
            updated.append(Self.linkPath)
        }
        return updated
    }
}
