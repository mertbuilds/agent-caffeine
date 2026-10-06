import Foundation

/// What the Lid closed pane and the menu say about the helper.
enum HelperSetup: Equatable {
    /// Never set up on this Mac.
    case notSetUp
    case requiresApproval
    case ready
    /// agent caffeine is bringing the helper back.
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

/// How long the repair of the helper waits at each step.
enum HelperRepair {
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
