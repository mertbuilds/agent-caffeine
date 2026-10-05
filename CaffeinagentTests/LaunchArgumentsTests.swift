import XCTest

final class LaunchArgumentsTests: XCTestCase {
    private let binary = "/Applications/agent caffeine.app/Contents/MacOS/caffeinagent"

    func testOnlyAPlainLaunchIsTheApp() {
        let cases: [(arguments: [String], kind: LaunchArguments.Kind)] = [
            ([], .app),
            (["-psn_0_123456"], .app),
            (["-NSDocumentRevisionsDebugMode", "YES"], .app),
            (["-AppleLanguages", "(en)", "-ApplePersistenceIgnoreState", "YES"], .app),
            (["--lab-record", "desk"], .lab),
            (["--lab-mark", "claude", "working", "a note"], .lab),
            (["--lab-score", "/tmp/x.jsonl"], .lab),
            (["-NSDocumentRevisionsDebugMode", "YES", "--lab-record", "desk"], .lab),
            (["--lab-nothing"], .lab),
            // What a hook entry or a script could pass by mistake.
            (["claude", "Stop", "v=1"], .refused("claude")),
            (["hook", "claude", "Stop"], .refused("hook")),
            (["--hook", "claude"], .refused("--hook")),
            (["--version"], .refused("--version")),
            (["-NSDocumentRevisionsDebugMode", "YES", "codex", "Stop"], .refused("codex")),
            ([""], .refused("")),
        ]
        for (arguments, kind) in cases {
            XCTAssertEqual(LaunchArguments.kind(of: [binary] + arguments), kind, "\(arguments)")
        }
        XCTAssertEqual(LaunchArguments.kind(of: []), .app)
    }

    /// The hooks run the small hook command, never the app binary.
    func testHookCommandsNeverNameTheAppBinary() {
        for entry in HookCatalog.entries {
            for event in entry.events {
                let command = HookCatalog.command(agent: entry.id, event: event)
                XCTAssertTrue(command.contains("/Contents/MacOS/CaffeinagentHook'"), command)
                XCTAssertFalse(command.contains("/Contents/MacOS/caffeinagent"), command)
            }
        }
        XCTAssertTrue(HookCatalog.pluginSource().contains("/Contents/MacOS/CaffeinagentHook"))
        XCTAssertFalse(HookCatalog.pluginSource().contains("/Contents/MacOS/caffeinagent"))
    }
}
