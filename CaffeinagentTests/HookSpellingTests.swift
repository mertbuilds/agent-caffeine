import XCTest

/// The hooks and the plugin files under both names of the bundle: what a
/// build before 1.0.2 wrote is recognised, is current where the two names
/// are one bundle, and is repaired where the earlier name is not on disk.
/// A temp folder stands in for the home folder.
final class HookSpellingTests: XCTestCase {
    private var home: URL!
    private let claude = HookCatalog.entry(id: "claude")!
    private let opencode = HookCatalog.entry(id: "opencode")!
    private let pi = HookCatalog.entry(id: "pi")!
    private let new = "/Applications/Agent Caffeine.app"
    private let earlier = "/Applications/agent caffeine.app"

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("hook-spelling-\(UUID().uuidString)")
        for entry in [claude, opencode, pi] {
            let file = home.appendingPathComponent(entry.configPath)
            let parts = entry.configPath.split(separator: "/")
            let folder = entry.format.jsonLayout == nil ? parts.prefix(parts.first == ".config" ? 2 : 1).reduce(home) { $0.appendingPathComponent(String($1)) } : file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    /// The install of 1.0.1, which knew one name.
    private var old: HookInstaller { HookInstaller(home: home, appPath: earlier) }
    /// A new install on the usual volume: the earlier name is the same bundle.
    private var onPlainVolume: HookInstaller { HookInstaller(home: home, appPath: new, spellings: AppPathSpellings(same: [earlier])) }
    /// A new install on a volume that tells names apart by case, with
    /// nothing at the earlier name.
    private var onStrictVolume: HookInstaller { HookInstaller(home: home, appPath: new, spellings: AppPathSpellings(gone: [earlier])) }
    /// The same volume with an install of 1.0.1 next to the new one.
    private var nextToTheOldInstall: HookInstaller { HookInstaller(home: home, appPath: new) }

    private func bytes(of entry: HookCatalogEntry) throws -> Data {
        try Data(contentsOf: old.configURL(for: entry))
    }

    private func text(of entry: HookCatalogEntry) throws -> String {
        String(decoding: try bytes(of: entry), as: UTF8.self)
    }

    private func write(_ text: String, for entry: HookCatalogEntry) throws {
        let url = old.configURL(for: entry)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func filesNextTo(_ entry: HookCatalogEntry) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: old.configURL(for: entry).deletingLastPathComponent().path).sorted()
    }

    // MARK: Entries in a config of the user

    func testEntriesWithTheOtherNameOfTheSameBundleAreCurrentAndStay() throws {
        try write("{\n  \"model\": \"some-model\"\n}\n", for: claude)
        try old.install(claude)
        let written = try bytes(of: claude)
        let files = try filesNextTo(claude)
        XCTAssertEqual(onPlainVolume.status(of: claude), .installed(version: HookCatalog.version))
        try onPlainVolume.install(claude)
        XCTAssertEqual(onPlainVolume.updateOwnFiles().map(\.id), [])
        XCTAssertEqual(try bytes(of: claude), written, "Not one byte is rewritten")
        XCTAssertEqual(try filesNextTo(claude), files, "And no backup is written")
        // The other way round: an install that kept the earlier name reads the new one.
        try old.uninstall(claude)
        try HookInstaller(home: home, appPath: new).install(claude)
        XCTAssertEqual(HookInstaller(home: home, appPath: earlier, spellings: AppPathSpellings(same: [new])).status(of: claude), .installed(version: HookCatalog.version))
    }

    func testEntriesWithANameThatIsNotOnDiskNeedAClick() throws {
        try write("{\n  \"model\": \"some-model\"\n}\n", for: claude)
        try old.install(claude)
        let written = try bytes(of: claude)
        for installer in [onStrictVolume, nextToTheOldInstall] {
            XCTAssertEqual(installer.status(of: claude), .outdated, "Settings offers Update")
            XCTAssertEqual(installer.updateOwnFiles().map(\.id), [], "The file is the user's: nothing changes at launch")
            XCTAssertEqual(try bytes(of: claude), written)
        }
        // "Update": the entries are replaced, not doubled.
        try onStrictVolume.install(claude)
        XCTAssertEqual(onStrictVolume.status(of: claude), .installed(version: HookCatalog.version))
        let updated = try text(of: claude)
        XCTAssertFalse(updated.contains(earlier))
        XCTAssertEqual(updated.components(separatedBy: HookCatalog.marker).count - 1, claude.rules.count * 2, "Each command names the hook twice")
        XCTAssertTrue(updated.contains("\"model\": \"some-model\""))
        // "Off" gives the file back as it was before the first "on".
        try onStrictVolume.uninstall(claude)
        XCTAssertEqual(try text(of: claude), "{\n  \"model\": \"some-model\"\n}\n")
    }

    func testOffTakesTheEntriesOfBothNames() throws {
        for (writer, remover) in [(old, onStrictVolume), (old, onPlainVolume), (onStrictVolume, old)] {
            try write("{}\n", for: claude)
            try writer.install(claude)
            XCTAssertTrue(try text(of: claude).contains(HookCatalog.marker))
            try remover.uninstall(claude)
            XCTAssertFalse(try text(of: claude).contains(HookCatalog.marker))
            XCTAssertEqual(remover.status(of: claude), .notInstalled)
        }
    }

    // MARK: Files of ours

    func testAFileWithTheOtherNameOfTheSameBundleIsCurrentAndStays() throws {
        for entry in [opencode, pi] {
            try old.install(entry)
            let written = try text(of: entry)
            XCTAssertTrue(written.contains("\"\(earlier)\(HookCatalog.marker)\""))
            XCTAssertEqual(onPlainVolume.status(of: entry), .installed(version: HookCatalog.pluginVersion(for: entry)))
            XCTAssertEqual(onPlainVolume.updateOwnFiles().map(\.id), [])
            try onPlainVolume.install(entry)
            XCTAssertEqual(try text(of: entry), written, "No rewrite for the name alone")
            try onPlainVolume.uninstall(entry)
            XCTAssertFalse(FileManager.default.fileExists(atPath: old.configURL(for: entry).path))
        }
    }

    /// The update of the version that every build does at launch still
    /// runs, and writes the name the bundle has on disk.
    func testAFileOfAnOlderVersionIsUpdatedUnderBothNames() throws {
        for (entry, version) in [(opencode, 1), (opencode, 2), (pi, 1)] {
            for (installer, path) in [(onPlainVolume, new), (onStrictVolume, new), (HookInstaller(home: home, appPath: earlier, spellings: AppPathSpellings(same: [new])), earlier)] {
                try write(try XCTUnwrap(HookPluginHistory.source(for: entry, version: version, appPath: earlier)), for: entry)
                XCTAssertEqual(installer.status(of: entry), .outdated)
                XCTAssertEqual(installer.updateOwnFiles().map(\.id), [entry.id], "\(entry.id) \(version) \(path)")
                XCTAssertEqual(try text(of: entry), HookCatalog.pluginSource(for: entry, appPath: path))
                try installer.uninstall(entry)
            }
        }
    }

    func testAFileWithANameThatIsNotOnDiskIsRepairedAtLaunch() throws {
        for entry in [opencode, pi] {
            try old.install(entry)
            XCTAssertEqual(onStrictVolume.status(of: entry), .outdated)
            XCTAssertEqual(onStrictVolume.updateOwnFiles().map(\.id), [entry.id])
            XCTAssertEqual(try text(of: entry), HookCatalog.pluginSource(for: entry, appPath: new))
            XCTAssertEqual(onStrictVolume.status(of: entry), .installed(version: HookCatalog.pluginVersion(for: entry)))
            XCTAssertEqual(try filesNextTo(entry), [old.configURL(for: entry).lastPathComponent], "The agent loads every file of the folder, so no backup is left there")
            XCTAssertEqual(onStrictVolume.updateOwnFiles().map(\.id), [], "The second time there is nothing to do")
        }
    }

    func testAFileThatIsNotOursToRepairIsLeftForTheUser() throws {
        let current = HookCatalog.pluginSource(for: opencode, appPath: earlier)
        // An install of 1.0.1 is at the earlier name: the file is its own.
        try write(current, for: opencode)
        XCTAssertEqual(nextToTheOldInstall.status(of: opencode), .outdated)
        XCTAssertEqual(nextToTheOldInstall.updateOwnFiles().map(\.id), [])
        XCTAssertEqual(try text(of: opencode), current)
        let kept = [
            // The user changed a line.
            current.replacingOccurrences(of: "let seq = 0;", with: "let seq = 100;"),
            current + "// my note\n",
            // The path of a copy in another folder, and a name no build wrote.
            HookCatalog.pluginSource(for: opencode, appPath: "/Users/me/Downloads/agent caffeine.app"),
            HookCatalog.pluginSource(for: opencode, appPath: "/Applications/AGENT CAFFEINE.app"),
        ]
        for text in kept {
            try write(text, for: opencode)
            XCTAssertEqual(onStrictVolume.status(of: opencode), .outdated)
            XCTAssertEqual(onStrictVolume.updateOwnFiles().map(\.id), [])
            XCTAssertEqual(try self.text(of: opencode), text)
        }
        // The user asks for the update: that still works.
        try onStrictVolume.install(opencode)
        XCTAssertEqual(try text(of: opencode), HookCatalog.pluginSource(for: opencode, appPath: new))
    }
}
