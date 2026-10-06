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
            (["--smoke-test", "8"], .smokeTest(seconds: 8)),
            (["-NSDocumentRevisionsDebugMode", "YES", "--smoke-test", "6.5"], .smokeTest(seconds: 6.5)),
            // Too short for two samples, too long, no number, nothing.
            (["--smoke-test", "2"], .refused("--smoke-test")),
            (["--smoke-test", "600"], .refused("--smoke-test")),
            (["--smoke-test", "long"], .refused("--smoke-test")),
            (["--smoke-test"], .refused("--smoke-test")),
            (["--smoke", "8"], .refused("--smoke")),
            // The probe of the displays reads only, and starts no app.
            (["--display-probe", "120"], .displayProbe(seconds: 120)),
            (["--display-probe", "0"], .refused("--display-probe")),
            (["--display-probe", "7200"], .refused("--display-probe")),
            (["--display-probe"], .refused("--display-probe")),
            (["--display", "8"], .refused("--display")),
            // What a hook entry or a script could pass by mistake.
            (["claude", "Stop", "v=1"], .refused("claude")),
            (["hook", "claude", "Stop"], .refused("hook")),
            (["--hook", "claude"], .refused("--hook")),
            (["--version"], .refused("--version")),
            (["-NSDocumentRevisionsDebugMode", "YES", "codex", "Stop"], .refused("codex")),
            ([""], .refused("")),
            // One dash is not enough: only the options the system passes.
            (["-h"], .refused("-h")),
            (["-lab-record", "desk"], .refused("-lab-record")),
            (["-v"], .refused("-v")),
            (["-"], .refused("-")),
            (["-NSDocumentRevisionsDebugMode", "YES", "-help"], .refused("-help")),
            (["-psn_0_123456", "-AppleLanguages", "(en)", "-NSQuitAlwaysKeepsWindows", "NO"], .app),
        ]
        for (arguments, kind) in cases {
            XCTAssertEqual(LaunchArguments.kind(of: [binary] + arguments), kind, "\(arguments)")
        }
        XCTAssertEqual(LaunchArguments.kind(of: []), .app)
    }

    func testSecondCopyDecision() {
        let cases: [(others: Int, waited: TimeInterval, want: SingleInstance.Decision)] = [
            (0, 0, .start),
            (0, 60, .start),
            (1, 0, .wait),
            (1, SingleInstance.waitLimit - SingleInstance.waitStep, .wait),
            (1, SingleInstance.waitLimit, .quit),
            (3, 100, .quit),
        ]
        for c in cases {
            XCTAssertEqual(SingleInstance.decision(others: c.others, waited: c.waited), c.want, "\(c.others) others after \(c.waited) s")
        }
    }

    /// The answers of `others` in order, the last one for ever. Gives
    /// whether the copy started, how often it asked and how long it slept.
    private func start(_ answers: [Int]) -> (started: Bool, asked: Int, slept: TimeInterval) {
        var asked = 0
        var slept: TimeInterval = 0
        let started = SingleInstance.mayStart(
            others: {
                asked += 1
                return answers[min(asked - 1, answers.count - 1)]
            },
            sleep: { slept += $0 }
        )
        return (started, asked, slept)
    }

    func testNoOtherCopyStartsAtOnce() {
        let got = start([0])
        XCTAssertTrue(got.started)
        XCTAssertEqual(got.asked, 1)
        XCTAssertEqual(got.slept, 0)
    }

    /// An update or the move to Applications: the old process is still
    /// there for a moment.
    func testCopyWaitsForTheOldOneToLeave() {
        let got = start([1, 1, 1, 0])
        XCTAssertTrue(got.started)
        XCTAssertEqual(got.asked, 4)
        XCTAssertEqual(got.slept, 3 * SingleInstance.waitStep, accuracy: 0.001)
    }

    func testSecondCopyLeavesWhenTheFirstStays() {
        let got = start([1])
        XCTAssertFalse(got.started)
        XCTAssertEqual(got.slept, SingleInstance.waitLimit, accuracy: 0.001)
        XCTAssertLessThan(got.asked, 100, "It gives up")
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

    func testReopenAction() {
        let cases: [(kind: LaunchArguments.Kind, anotherCopyRuns: Bool, iconHidden: Bool, want: Reopen.Action)] = [
            (.app, false, false, .start),
            // A hidden icon never keeps the app from starting.
            (.app, false, true, .start),
            (.app, true, false, .quit),
            (.app, true, true, .askRunningCopy),
            // A command is no launch of the app, whatever else is true.
            (.lab, false, false, .runLab),
            (.lab, true, true, .runLab),
            // The smoke test runs next to a copy that is installed.
            (.smokeTest(seconds: 8), false, false, .runSmokeTest(seconds: 8)),
            (.smokeTest(seconds: 8), true, true, .runSmokeTest(seconds: 8)),
            (.displayProbe(seconds: 60), true, true, .runDisplayProbe(seconds: 60)),
            (.refused("-h"), false, false, .refuse("-h")),
            (.refused("claude"), true, true, .refuse("claude")),
        ]
        for c in cases {
            XCTAssertEqual(Reopen.action(kind: c.kind, anotherCopyRuns: c.anotherCopyRuns, iconHidden: c.iconHidden), c.want, "\(c)")
        }
    }

    /// Without the icon, opening the app again is the only way to Preferences.
    func testRunningCopyShowsPreferencesOnlyWhenTheIconIsHidden() {
        XCTAssertTrue(Reopen.showsPreferences(iconHidden: true))
        XCTAssertFalse(Reopen.showsPreferences(iconHidden: false))
    }
}
