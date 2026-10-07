import Foundation

/// What macOS says about the app as a login item.
enum LoginItemStatus: Equatable {
    case notRegistered
    case enabled
    /// The user turned it off in System Settings > General > Login Items.
    case requiresApproval
    case notFound
}

/// "Open agent caffeine at login" as Settings shows it.
enum LoginItemState: Equatable {
    case on
    case off
    /// Registered, and turned off in Login Items.
    case needsApproval
    /// The app does not run from the Applications folder.
    case unavailable

    /// A copy outside the Applications folder is never a login item: it
    /// moves away, and macOS would open a path that is gone.
    static func state(status: LoginItemStatus, inApplications: Bool) -> LoginItemState {
        guard inApplications else { return .unavailable }
        switch status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        case .notRegistered, .notFound: return .off
        }
    }

    /// What the switch shows. Registered counts as on, also while macOS
    /// waits for the user to allow it.
    var isOn: Bool { self == .on || self == .needsApproval }
}

/// The registration of the app as a login item. `SMAppService.mainApp`
/// in the app.
protocol LoginItemManaging {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}
