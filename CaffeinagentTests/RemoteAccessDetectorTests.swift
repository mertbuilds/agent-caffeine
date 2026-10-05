import XCTest

final class RemoteAccessDetectorTests: XCTestCase {
    typealias Settings = RemoteAccessDetector.ClaudeSettings

    func testClaudeRemoteControl() {
        let cases: [(name: String, sessions: [[String]], settings: Settings, expected: Bool)] = [
            ("no session", [], Settings(atStartup: true), false),
            ("plain session", [["--dangerously-skip-permissions"]], Settings(), false),
            ("server mode", [["remote-control"]], Settings(), true),
            ("server mode with options", [["remote-control", "--spawn", "worktree"]], Settings(), true),
            ("long flag", [["--remote-control", "My Project"]], Settings(), true),
            ("short flag", [["--model", "x", "--rc"]], Settings(), true),
            ("on for all sessions", [[]], Settings(atStartup: true), true),
            ("on for all sessions, headless run", [["-p", "x"]], Settings(atStartup: true), false),
            ("on for all sessions, print flag", [["--print"]], Settings(atStartup: true), false),
            ("one of two sessions", [["-p"], ["--rc"]], Settings(), true),
            ("switched off for good", [["remote-control"], []], Settings(atStartup: true, disabled: true), false),
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
