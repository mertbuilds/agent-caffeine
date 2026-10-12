import XCTest

final class RemoteAccessDetectorTests: XCTestCase {
    typealias Settings = RemoteAccessDetector.ClaudeSettings

    func testClaudeRemoteControl() {
        typealias Session = RemoteAccessDetector.ClaudeSession
        func terminal(_ arguments: [String]) -> Session { Session(arguments: arguments, hasTerminal: true) }
        func noTerminal(_ arguments: [String]) -> Session { Session(arguments: arguments, hasTerminal: false) }
        let cases: [(name: String, sessions: [Session], settings: Settings, expected: Bool)] = [
            ("no session", [], Settings(atStartup: true), false),
            ("plain session", [terminal(["--dangerously-skip-permissions"])], Settings(), false),
            ("server mode", [terminal(["remote-control"])], Settings(), true),
            ("server mode with options", [terminal(["remote-control", "--spawn", "worktree"])], Settings(), true),
            ("server mode without a terminal", [noTerminal(["remote-control"])], Settings(), true),
            ("long flag", [terminal(["--remote-control", "My Project"])], Settings(), true),
            ("short flag", [terminal(["--model", "x", "--rc"])], Settings(), true),
            ("on for all sessions", [terminal([])], Settings(atStartup: true), true),
            ("on for all sessions, headless run", [terminal(["-p", "x"])], Settings(atStartup: true), false),
            ("on for all sessions, print flag", [terminal(["--print"])], Settings(atStartup: true), false),
            ("one of two sessions", [terminal(["-p"]), terminal(["--rc"])], Settings(), true),
            ("switched off for good", [terminal(["remote-control"]), terminal([])], Settings(atStartup: true, disabled: true), false),
            // Only a session that a person sits at.
            ("SDK session of another app", [noTerminal(["--output-format", "stream-json", "--input-format", "stream-json", "--verbose"])], Settings(atStartup: true), false),
            ("SDK session in a terminal", [terminal(["--input-format", "stream-json"])], Settings(atStartup: true), false),
            ("SDK session, joined flag", [terminal(["--input-format=stream-json"])], Settings(atStartup: true), false),
            ("session without a terminal", [noTerminal([])], Settings(atStartup: true), false),
            ("mcp server", [noTerminal(["mcp", "serve"])], Settings(atStartup: true), false),
            ("mcp command in a terminal", [terminal(["mcp", "list"])], Settings(atStartup: true), false),
            ("flag on a headless run", [terminal(["-p", "x", "--rc"])], Settings(), false),
            ("flag without a terminal", [noTerminal(["--rc"])], Settings(), false),
            ("an SDK session next to a real one", [noTerminal(["--input-format", "stream-json"]), terminal(["--resume", "7c1e"])], Settings(atStartup: true), true),
        ]
        for c in cases {
            XCTAssertEqual(RemoteAccessDetector.claudeRemoteControl(sessions: c.sessions, settings: c.settings), c.expected, c.name)
        }
    }

    func testSettingsTakeOnlyTheTwoSwitches() {
        XCTAssertEqual(Settings(json: Data(#"{"remoteControlAtStartup": true, "env": {"A": "b"}}"#.utf8)), Settings(atStartup: true))
        XCTAssertEqual(Settings(json: Data(#"{"disableRemoteControl": true}"#.utf8)), Settings(disabled: true))
        XCTAssertEqual(Settings(json: Data(#"{"remoteControlAtStartup": "yes"}"#.utf8)), Settings())
        XCTAssertEqual(Settings(json: Data("not json".utf8)), Settings())
    }

    func testSettingIsOnByDefaultAndSurvivesOldSettings() throws {
        XCTAssertTrue(DetectionSettings().stayAwakeForRemoteAccess)
        let old = try JSONDecoder().decode(DetectionSettings.self, from: Data(#"{"waitingHold": 60}"#.utf8))
        XCTAssertTrue(old.stayAwakeForRemoteAccess)
        var changed = DetectionSettings()
        changed.stayAwakeForRemoteAccess = false
        XCTAssertFalse(try JSONDecoder().decode(DetectionSettings.self, from: JSONEncoder().encode(changed)).stayAwakeForRemoteAccess)
    }
}
