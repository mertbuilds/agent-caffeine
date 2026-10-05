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
        /// Not a launch of the app and not a known command.
        case refused(String)
    }

    /// The options Launch Services and Xcode pass: `-psn_0_1`,
    /// `-NSDocumentRevisionsDebugMode YES`, `-AppleLanguages (en)`. Any
    /// other option with one dash is a typo or a guess (`-h`, `-lab-record`).
    static let systemOptionPrefixes = ["-psn_", "-NS", "-Apple"]

    /// `arguments` starts with the path of the binary. A system option
    /// has at most one value.
    static func kind(of arguments: [String]) -> Kind {
        let rest = Array(arguments.dropFirst())
        if rest.contains(where: { $0.hasPrefix("--lab-") }) { return .lab }
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
