import Foundation

// Shared by the app and the root helper. The helper takes two booleans and
// nothing else from its client: no strings, no paths.
@objc protocol SleepFlagHelperProtocol {
    // Replies with the value read back from the kernel.
    func setSleepDisabled(_ on: Bool, reply: @escaping (Bool) -> Void)
    func status(reply: @escaping (_ sleepDisabled: Bool, _ setByHelper: Bool, _ version: String) -> Void)
    // Replies with the current value, so the app sees a flag the helper
    // cleared on its own.
    func heartbeat(reply: @escaping (Bool) -> Void)
    // After an update of the app: the helper clears a flag it owns, replies
    // and exits. launchd starts the binary that is in the bundle now on the
    // next connection, and nothing about the registration changes.
    func retire(reply: @escaping () -> Void)
}

enum SleepFlagHelper {
    static let appBundleID = "com.caffeinagent.app"
    static let label = "com.caffeinagent.app.helper"
    static let machServiceName = label
    static let plistName = "\(label).plist"
    static let teamID = "3HGP3W3TLD"
    static let heartbeatInterval: TimeInterval = 15
    static let heartbeatTimeout: TimeInterval = 60

    // Developer ID signed by this team with the given identifier. An ad hoc
    // Debug build never satisfies it.
    static func requirement(identifier: String) -> String {
        "anchor apple generic and identifier \"\(identifier)\""
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            + " and certificate leaf[subject.OU] = \"\(teamID)\""
    }
}
