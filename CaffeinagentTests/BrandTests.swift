import CryptoKit
import XCTest

/// The brand is written "Agent Caffeine" in every text people read. The
/// path of the app and the files the app writes for the agents keep the
/// old lowercase name, because installed hooks point to them.
final class BrandTests: XCTestCase {
    private static let lowercaseBrand = "agent caffeine"

    func testNoTextOfThePanelHasTheLowercaseBrand() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Caffeinagent/UI/Panel/Model/PanelText.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(source.contains("Agent Caffeine"))
        for (index, line) in source.components(separatedBy: "\n").enumerated() where line.contains(Self.lowercaseBrand) {
            XCTFail("PanelText.swift line \(index + 1) has the lowercase brand: \(line)")
        }
        let samples = [
            PanelText.offTitle, PanelText.pausedTitle, PanelText.stoppedTitle, PanelText.quit, PanelText.mainSwitch,
            PanelText.openAtLogin, PanelText.menuBar("Your Mac stays awake"),
        ]
        for text in samples {
            XCTAssertFalse(text.contains(Self.lowercaseBrand), text)
            XCTAssertTrue(text.contains("Agent Caffeine"), text)
        }
    }

    /// The names a machine reads keep the lowercase form: the path of the
    /// app, the comment at the top of the plugins the app writes (their text
    /// is compared with what an installed build wrote), and the label of
    /// the Keychain item. Every other line is for people.
    func testNoTextPeopleReadHasTheLowercaseBrand() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let folders = ["Caffeinagent", "CaffeinagentCLI", "CaffeinagentHelper", "CaffeinagentHook", "release-notes", "skills"]
        var files = ["README.md", "THIRD_PARTY_NOTICES.md", "project.yml", "scripts/release.sh", "scripts/dmg-background.html", "scripts/dmg-settings.py"]
            .map { root.appendingPathComponent($0) }
        for folder in folders {
            let found = try XCTUnwrap(FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil), folder)
            files += found.compactMap { $0 as? URL }.filter { ["swift", "plist", "md", "strings", "entitlements"].contains($0.pathExtension) }
        }
        XCTAssertGreaterThan(files.count, 100)
        let machineLines = [
            "// Written by agent caffeine. Turn it off in agent caffeine > Preferences > Agents.",
            "// It tells agent caffeine when ",
            "add[kSecAttrLabel as String] = \"agent caffeine license\"",
        ]
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in source.components(separatedBy: "\n").enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if machineLines.contains(where: { trimmed.hasPrefix($0) }) { continue }
                let rest = line.replacingOccurrences(of: "agent caffeine.app", with: "").replacingOccurrences(of: "Agent Caffeine", with: "")
                if rest.range(of: "agent caffeine", options: .caseInsensitive) != nil {
                    XCTFail("\(file.lastPathComponent) line \(index + 1) does not write the brand as Agent Caffeine: \(trimmed)")
                }
            }
        }
    }

    /// The name of the volume is the title of the install window.
    func testTheDiskImageIsNamedAfterTheBrand() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let release = try String(contentsOf: root.appendingPathComponent("scripts/release.sh"), encoding: .utf8)
        XCTAssertTrue(release.contains("-s scripts/dmg-settings.py \\\n  \"Agent Caffeine\" \\\n"))
        let art = try String(contentsOf: root.appendingPathComponent("scripts/dmg-background.html"), encoding: .utf8)
        XCTAssertTrue(art.contains("<div class=\"wm\">Agent Caffeine</div>"))
        XCTAssertTrue(art.contains("drag <b>Agent Caffeine</b> to"))
    }

    /// A change here marks the files of every installed user as outdated
    /// or edited, and their hooks point to this path.
    func testThePathOfTheAppAndTheWrittenFilesDoNotChange() throws {
        XCTAssertEqual(HookCatalog.stableAppPath, "/Applications/agent caffeine.app")
        let opencode = try XCTUnwrap(HookCatalog.entry(id: "opencode"))
        let pi = try XCTUnwrap(HookCatalog.entry(id: HookCatalog.piID))
        let path = HookCatalog.stableAppPath
        let texts: [(String, String?, String)] = [
            ("opencode 1", HookPluginHistory.source(for: opencode, version: 1, appPath: path), "c8b6605a646d9b0f1cebca66cd9d0d2fad16ec122ad978859dbcada74cd1ece4"),
            ("opencode 2", HookPluginHistory.source(for: opencode, version: 2, appPath: path), "fd4f4495f547524314a5d54390d48fed75d8d362cbd138a4c24ca07b25d24607"),
            ("pi 1", HookPluginHistory.source(for: pi, version: 1, appPath: path), "e1eafb9e66032277424d05c092b47bd2a20457b8aafb2a48cba85b3e8c5b0c5b"),
            ("opencode now", HookCatalog.pluginSource(appPath: path), "5788c7a2f7f7b2c7081ac9c8e1f608f299753d6be81d5bd4f546c8993d3c932d"),
            ("pi now", HookCatalog.piExtensionSource(appPath: path), "72aa0f8ec51f43575533213a766e897743fb016a0adf548ea9cccec7a45b801a"),
        ]
        for (name, text, expected) in texts {
            let text = try XCTUnwrap(text, name)
            let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, expected, name)
        }
    }
}
