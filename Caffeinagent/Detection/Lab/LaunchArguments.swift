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

    /// `arguments` starts with the path of the binary. Launch Services and
    /// Xcode pass options with one dash (`-psn_0_1`, `-NSDocumentRevisionsDebugMode YES`,
    /// `-AppleLanguages (en)`), each with at most one value.
    static func kind(of arguments: [String]) -> Kind {
        let rest = Array(arguments.dropFirst())
        if rest.contains(where: { $0.hasPrefix("--lab-") }) { return .lab }
        var index = 0
        while index < rest.count {
            let argument = rest[index]
            guard argument.hasPrefix("-"), !argument.hasPrefix("--") else { return .refused(argument) }
            index += index + 1 < rest.count && !rest[index + 1].hasPrefix("-") ? 2 : 1
        }
        return .app
    }
}
