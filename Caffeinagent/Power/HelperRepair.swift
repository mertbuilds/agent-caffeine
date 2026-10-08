import Foundation

/// What the Lid closed pane and the menu say about the helper.
enum HelperSetup: Equatable {
    /// Never set up on this Mac.
    case notSetUp
    case requiresApproval
    case ready
    /// Agent Caffeine is bringing the helper back.
    case repairing
    /// No answer, or a repair that did not bring the helper back yet.
    case notResponding
    /// It was set up before and is gone, and only the user can set it up again.
    case lost
}

/// Why a flag value goes to the helper, for the log.
enum FlagReason: String {
    case decision
    case retry
    case heartbeat
    case connectionLost = "connection lost"
    case repair
    case replace = "the helper is replaced"
    case remove = "the helper is removed"
    case quit
}

/// What to do with the helper that runs when the app starts.
enum HelperReplacement: Equatable {
    case keep
    /// It is asked to leave, and launchd starts the binary that is in the
    /// bundle now. Nothing about the registration changes.
    case retire
    /// Removed and registered again. macOS has refused to register right
    /// after a removal, so this is the last way.
    case registerAgain
}

/// How long the repair of the helper waits at each step.
enum HelperRepair {
    /// After an update the helper that runs is the binary of the version
    /// before it: launchd keeps the process it started.
    /// - Parameters:
    ///   - running: the version the helper gave, nil when it gave none.
    ///   - retired: it was asked to leave before, in this replacement.
    static func replacement(running: String?, app: String, retired: Bool) -> HelperReplacement {
        guard let running else { return .registerAgain }
        if running == app { return .keep }
        // A helper of a build that does not know how to leave, or one that
        // did not start again as the new binary.
        return retired ? .registerAgain : .retire
    }

    /// The helper that launchd starts after a retire is asked this often,
    /// this far apart.
    static let retireTries = 3
    static let retireInterval: TimeInterval = 0.5

    /// A new connection is tried this often before the helper is registered again.
    static let reconnectTries = 2
    static let pollInterval: TimeInterval = 0.25
    /// For the registration to be gone after unregister().
    static let removalPatience: TimeInterval = 10
    /// The waits after each register() that was not permitted.
    static let registerBackoff: [TimeInterval] = [0.5, 1, 2, 4]
    /// For the registration to be enabled after register().
    static let enablePatience: TimeInterval = 10
    static let firstAnswerTries = 3
    static let firstAnswerInterval: TimeInterval = 1
    /// A helper the repair took away is registered again this often, this
    /// many times in a launch.
    static let slowRetryInterval: TimeInterval = 60
    static let slowRetries = 5

    /// register() right after unregister() ends with "Operation not
    /// permitted": the system still has the old registration on record. Seen
    /// on macOS 26 as code 1 from ServiceManagement, 19 ms after the removal.
    /// Two minutes later the same call passed.
    static func isNotPermitted(_ error: Error) -> Bool {
        let error = error as NSError
        return error.code == Int(EPERM) && ["SMAppServiceErrorDomain", NSPOSIXErrorDomain].contains(error.domain)
    }

    static func describe(_ error: Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code): \(error.localizedDescription)"
    }
}
