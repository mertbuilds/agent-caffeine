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
        /// `--display-probe <seconds>`: prints what the lid and the
        /// displays do, and starts no app. See `DisplayProbe`.
        case displayProbe(seconds: TimeInterval)
        /// `--hotspot-probe <name> [--join] [--seconds N]`: prints what a
        /// scan for one hotspot sees, and starts no app. See `HotspotProbe`.
        case hotspotProbe(HotspotProbeOptions)
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

    static let displayProbeOption = "--display-probe"
    static let displayProbeSeconds: ClosedRange<TimeInterval> = 1...3600

    static let hotspotProbeOption = "--hotspot-probe"
    static let hotspotProbeSeconds: ClosedRange<TimeInterval> = 1...3600

    /// What stands after `--hotspot-probe`: the name, then `--join` and
    /// `--seconds N` in any order. Nil for anything else.
    static func hotspotProbe(_ rest: [String]) -> HotspotProbeOptions? {
        guard let first = rest.first, !first.hasPrefix("--"), let name = HotspotName.cleaned(first) else { return nil }
        var options = HotspotProbeOptions(name: name)
        var index = 1
        while index < rest.count {
            switch rest[index] {
            case "--join":
                options.join = true
                index += 1
            case "--seconds":
                guard index + 1 < rest.count, let seconds = TimeInterval(rest[index + 1]), hotspotProbeSeconds.contains(seconds) else { return nil }
                options.seconds = seconds
                index += 2
            default:
                return nil
            }
        }
        return options
    }

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
        if let index = rest.firstIndex(of: displayProbeOption) {
            guard index + 1 < rest.count, let seconds = TimeInterval(rest[index + 1]), displayProbeSeconds.contains(seconds) else {
                return .refused(displayProbeOption)
            }
            return .displayProbe(seconds: seconds)
        }
        if let index = rest.firstIndex(of: hotspotProbeOption) {
            guard let options = hotspotProbe(Array(rest[(index + 1)...])) else { return .refused(hotspotProbeOption) }
            return .hotspotProbe(options)
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

/// What `--hotspot-probe` was asked for.
struct HotspotProbeOptions: Equatable {
    /// The name of the hotspot to look for. The probe prints no other
    /// network name.
    var name: String
    /// Join the hotspot once, when a scan first finds it.
    var join = false
    var seconds: TimeInterval = 60
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

/// What a start of the binary does, and how a copy that runs comes back:
/// opening the app again shows Preferences. Without the icon that is the
/// only way in, and macOS hides the icon on its own when the menu bar is
/// full or the notch covers it, which the app cannot see.
enum Reopen {
    enum Action: Equatable {
        case runLab
        case runSmokeTest(seconds: TimeInterval)
        case runDisplayProbe(seconds: TimeInterval)
        case runHotspotProbe(HotspotProbeOptions)
        case refuse(String)
        case start
        /// Another copy runs: this one asks it to show Preferences, then
        /// leaves.
        case askRunningCopy
    }

    /// The running copy shows Preferences when it gets this. It carries
    /// nothing.
    static let notificationName = "com.caffeinagent.app.showPreferences"

    /// `anotherCopyRuns` counts only for a plain launch.
    static func action(kind: LaunchArguments.Kind, anotherCopyRuns: Bool) -> Action {
        switch kind {
        case .lab: return .runLab
        case .smokeTest(let seconds): return .runSmokeTest(seconds: seconds)
        case .displayProbe(let seconds): return .runDisplayProbe(seconds: seconds)
        case .hotspotProbe(let options): return .runHotspotProbe(options)
        case .refused(let argument): return .refuse(argument)
        case .app:
            return anotherCopyRuns ? .askRunningCopy : .start
        }
    }
}

/// Whether a reopen shows Preferences. macOS can send a reopen when the
/// user clicks a notification of the app, and that click goes to the agent
/// and must never open Preferences. The two come in either order, so a
/// reopen waits a moment for the click. A second launch of the app does
/// not come through here: it shows Preferences at once.
struct ReopenGate {
    /// How long a reopen waits for the click of a notification.
    static let wait: TimeInterval = 0.4
    /// A reopen this soon after the click belongs to the click.
    static let afterClick: TimeInterval = 1

    private var lastClick: TimeInterval?
    private var pending: Int?
    private var reopens = 0

    /// The user clicked a notification. A reopen that waits is dropped.
    mutating func notificationClicked(at now: TimeInterval) {
        lastClick = now
        pending = nil
    }

    /// Nil when the reopen belongs to a click. Else what to hand to
    /// `waitEnded` after `wait`.
    mutating func reopened(at now: TimeInterval) -> Int? {
        if let lastClick, now - lastClick <= Self.afterClick { return nil }
        reopens += 1
        pending = reopens
        return reopens
    }

    /// True when Preferences opens now: no click came, and no later
    /// reopen waits in place of this one.
    mutating func waitEnded(_ reopen: Int) -> Bool {
        guard pending == reopen else { return false }
        pending = nil
        return true
    }
}
