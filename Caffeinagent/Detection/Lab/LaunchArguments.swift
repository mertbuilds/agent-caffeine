import Foundation

/// What the app binary was started for. The menu bar app must come up only
/// from a plain launch: a second copy would take power assertions of its
/// own. So arguments that look like a command and are none do not fall
/// through to the app. The hooks never start this binary at all: they run
/// `CaffeinagentHook`.
enum LaunchArguments {
    enum Kind: Equatable {
        case app
        case lab
        /// `--smoke-test <seconds>`: the app starts, measures itself and
        /// leaves. See `SmokeTest`.
        case smokeTest(seconds: TimeInterval)
        /// Not a launch of the app and not a known command.
        case refused(String)
    }

    /// The options Launch Services and Xcode pass: `-psn_0_1`,
    /// `-NSDocumentRevisionsDebugMode YES`, `-AppleLanguages (en)`. Any
    /// other option with one dash is a typo or a guess (`-h`, `-lab-record`).
    static let systemOptionPrefixes = ["-psn_", "-NS", "-Apple"]

    static let smokeTestOption = "--smoke-test"
    /// Shorter than this and the engine has no time for two samples.
    static let smokeTestSeconds: ClosedRange<TimeInterval> = 6...120

    /// `arguments` starts with the path of the binary. A system option
    /// has at most one value.
    static func kind(of arguments: [String]) -> Kind {
        let rest = Array(arguments.dropFirst())
        if rest.contains(where: { $0.hasPrefix("--lab-") }) { return .lab }
        if let index = rest.firstIndex(of: smokeTestOption) {
            guard index + 1 < rest.count, let seconds = TimeInterval(rest[index + 1]), smokeTestSeconds.contains(seconds) else {
                return .refused(smokeTestOption)
            }
            return .smokeTest(seconds: seconds)
        }
        var index = 0
        while index < rest.count {
            let argument = rest[index]
            guard systemOptionPrefixes.contains(where: argument.hasPrefix) else { return .refused(argument) }
            index += index + 1 < rest.count && !rest[index + 1].hasPrefix("-") ? 2 : 1
        }
        return .app
    }
}

/// A plain launch starts the app only when no other copy runs: a start
/// from the terminal with no arguments, or of a second copy in another
/// folder, would take power assertions of its own.
///
/// A copy that starts while the old one is on its way out waits for it:
/// Sparkle starts the new version when the old process is gone, and the
/// move to the Applications folder opens the new copy just before the old
/// one quits.
enum SingleInstance {
    enum Decision: Equatable {
        case start
        case wait
        case quit
    }

    static let waitLimit: TimeInterval = 5
    static let waitStep: TimeInterval = 0.25

    /// `others` is the number of other running copies with our bundle
    /// identifier, `waited` the seconds waited so far.
    static func decision(others: Int, waited: TimeInterval) -> Decision {
        if others <= 0 { return .start }
        return waited < waitLimit ? .wait : .quit
    }

    /// False when this copy has to leave. `others` is asked again after
    /// each wait.
    static func mayStart(others: () -> Int, sleep: (TimeInterval) -> Void) -> Bool {
        var waited: TimeInterval = 0
        while true {
            switch decision(others: others(), waited: waited) {
            case .start: return true
            case .quit: return false
            case .wait:
                sleep(waitStep)
                waited += waitStep
            }
        }
    }
}

/// What a start of the binary does, and how a copy that runs comes back
/// when its icon is hidden: without the icon, opening the app again is the
/// only way to Preferences.
enum Reopen {
    enum Action: Equatable {
        case runLab
        case runSmokeTest(seconds: TimeInterval)
        case refuse(String)
        case start
        /// Another copy runs: this one leaves.
        case quit
        /// Another copy runs with its icon hidden: this one asks it to
        /// show Preferences, then leaves.
        case askRunningCopy
    }

    /// The running copy shows Preferences when it gets this. It carries
    /// nothing, and the running copy decides for itself.
    static let notificationName = "com.caffeinagent.app.showPreferences"

    /// `anotherCopyRuns` counts only for a plain launch.
    static func action(kind: LaunchArguments.Kind, anotherCopyRuns: Bool, iconHidden: Bool) -> Action {
        switch kind {
        case .lab: return .runLab
        case .smokeTest(let seconds): return .runSmokeTest(seconds: seconds)
        case .refused(let argument): return .refuse(argument)
        case .app:
            guard anotherCopyRuns else { return .start }
            return iconHidden ? .askRunningCopy : .quit
        }
    }

    /// Whether the copy that runs shows Preferences when the user opens
    /// the app again. With the icon shown, the menu is the way in.
    static func showsPreferences(iconHidden: Bool) -> Bool {
        iconHidden
    }
}
