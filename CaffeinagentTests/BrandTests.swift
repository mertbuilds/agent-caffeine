import CryptoKit
import XCTest

/// The brand is written "Agent Caffeine" in every text people read, and
/// the bundle is `Agent Caffeine.app` from 1.0.2. The earlier name of the
/// bundle stays known, and the comment in the files the app writes for
/// the agents keeps the lowercase name.
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
    /// app as 1.0.0 and 1.0.1 installed it, the comment at the top of the
    /// plugins the app writes (their text is compared with what an
    /// installed build wrote), and the label of the Keychain item. Every
    /// other line is for people.
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

    /// The bundle is `Agent Caffeine.app` from 1.0.2, and the name of 1.0.0
    /// and 1.0.1 stays known for good: installed hooks, plugins and links
    /// hold it, and an update keeps the name of the bundle it replaces.
    func testTheBundleHasTheBrandAsItsNameAndTheEarlierNameStaysKnown() throws {
        XCTAssertEqual(AppInstall.bundleName, "Agent Caffeine.app")
        XCTAssertEqual(AppInstall.earlierBundleName, "agent caffeine.app")
        XCTAssertEqual(AppInstall.knownPaths, ["/Applications/Agent Caffeine.app", "/Applications/agent caffeine.app"])
        XCTAssertEqual(HookCatalog.stableAppPath, "/Applications/Agent Caffeine.app")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let release = try String(contentsOf: root.appendingPathComponent("scripts/release.sh"), encoding: .utf8)
        XCTAssertTrue(release.contains("\nDIST_NAME=\"Agent Caffeine.app\"\n"), "The bundle in the disk image")
        XCTAssertFalse(release.contains("/agent caffeine.app"), "No build is named as 1.0.1 was")
    }

    /// What does not change with the name of the bundle: the binary of the
    /// app, the command and the first lines of the plugins the app writes.
    func testTheNamesAMachineReadsDoNotChange() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let project = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        XCTAssertTrue(project.contains("        PRODUCT_NAME: caffeinagent\n"), "The binary, and the product of Xcode that release.sh copies")
        XCTAssertTrue(project.contains("        PRODUCT_BUNDLE_IDENTIFIER: com.caffeinagent.app\n"))
        XCTAssertEqual(CommandLineSetup.toolName, "agent-caffeine")
        XCTAssertEqual(CommandLineSetup.pathInApp, "/Contents/MacOS/agent-caffeine")
        XCTAssertEqual(HookCatalog.marker, "/Contents/MacOS/CaffeinagentHook")
        let comment = "// Written by agent caffeine. Turn it off in agent caffeine > Preferences > Agents.\n"
        for path in AppInstall.knownPaths {
            XCTAssertTrue(HookCatalog.pluginSource(appPath: path).hasPrefix("// agent-caffeine-hook v=\(HookCatalog.pluginVersion)\n" + comment + "// It tells agent caffeine when opencode works"))
            XCTAssertTrue(HookCatalog.piExtensionSource(appPath: path).hasPrefix("// agent-caffeine-hook v=\(HookCatalog.piExtensionVersion)\n" + comment + "// It tells agent caffeine when Pi works"))
        }
    }

    /// The files hold the path of the app, so each text has one form per
    /// name of the bundle. A change of a digest here marks the files of
    /// installed users as outdated or edited. The texts of the builds
    /// before 1.0.2 were only ever written with the earlier name.
    func testTheWrittenFilesDoNotChange() throws {
        let opencode = try XCTUnwrap(HookCatalog.entry(id: "opencode"))
        let pi = try XCTUnwrap(HookCatalog.entry(id: HookCatalog.piID))
        let earlier = "/Applications/agent caffeine.app", new = "/Applications/Agent Caffeine.app"
        let texts: [(String, String?, String)] = [
            ("opencode 1", HookPluginHistory.source(for: opencode, version: 1, appPath: earlier), "c8b6605a646d9b0f1cebca66cd9d0d2fad16ec122ad978859dbcada74cd1ece4"),
            ("opencode 2", HookPluginHistory.source(for: opencode, version: 2, appPath: earlier), "fd4f4495f547524314a5d54390d48fed75d8d362cbd138a4c24ca07b25d24607"),
            ("pi 1", HookPluginHistory.source(for: pi, version: 1, appPath: earlier), "e1eafb9e66032277424d05c092b47bd2a20457b8aafb2a48cba85b3e8c5b0c5b"),
            ("opencode now, earlier name", HookCatalog.pluginSource(appPath: earlier), "5788c7a2f7f7b2c7081ac9c8e1f608f299753d6be81d5bd4f546c8993d3c932d"),
            ("pi now, earlier name", HookCatalog.piExtensionSource(appPath: earlier), "72aa0f8ec51f43575533213a766e897743fb016a0adf548ea9cccec7a45b801a"),
            ("opencode now, new name", HookCatalog.pluginSource(appPath: new), "2f0c1cd25fc78d4b7c8f0a178c534e41bd031ee73acfaca4ddb6c686038b0927"),
            ("pi now, new name", HookCatalog.piExtensionSource(appPath: new), "4c1dd4a1db3d4c6a29a59429dd5c5ebc6e4e833c9d619adf69112988fef67bfd"),
        ]
        for (name, text, expected) in texts {
            let text = try XCTUnwrap(text, name)
            let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, expected, name)
        }
        // The two forms of a text differ in the path of the hook command and in nothing else.
        XCTAssertEqual(HookCatalog.pluginSource(appPath: new).replacingOccurrences(of: new, with: earlier), HookCatalog.pluginSource(appPath: earlier))
        XCTAssertEqual(HookCatalog.piExtensionSource(appPath: new).replacingOccurrences(of: new, with: earlier), HookCatalog.piExtensionSource(appPath: earlier))
    }
}
