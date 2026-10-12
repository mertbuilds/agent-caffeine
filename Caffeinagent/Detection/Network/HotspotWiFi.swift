import Foundation

/// Why the Mac did not join the hotspot.
enum HopFailure: String, Equatable, CaseIterable {
    /// The hotspot refused the password.
    case wrongPassword
    /// macOS hides the names of Wi-Fi networks from Agent Caffeine:
    /// Location Services is off for it.
    case noPermission
    /// Wi-Fi is switched off. Agent Caffeine never switches it on.
    case wifiOff
    /// This Mac has no Wi-Fi.
    case noWiFi
    /// The password is not in the Keychain, or cannot be read.
    case noPassword
    /// macOS gave no answer in time.
    case timeout
    case other
}

/// A network a scan saw.
struct WiFiSighting: Equatable {
    /// The signal in dBm.
    var rssi: Int
    var channel: Int
}

enum WiFiScan: Equatable {
    case found(WiFiSighting)
    /// The scan ran, and the name is not on the air.
    case notFound
    case failed(HopFailure)
}

enum WiFiJoin: Equatable {
    case joined
    case failed(HopFailure)
}

/// The Wi-Fi of the Mac, so a test can pass any air. Every call can
/// block for seconds and is made off the main thread.
///
/// A name is matched as `HotspotName.matches` has it. Nothing here
/// switches Wi-Fi on or off.
protocol WiFiAccess {
    /// Nil on a Mac with no Wi-Fi.
    func power() -> Bool?
    /// The name of the network the Mac is on. Nil when it is on none,
    /// and when macOS hides the name.
    func currentNetwork() -> String?
    /// A scan for this one name.
    func scan(for name: String) -> WiFiScan
    /// Joins a network that a scan found.
    /// - Parameter password: nil for a network macOS knows already: the
    ///   password of such a network is in the keychain of the system.
    func associate(to name: String, password: String?) -> WiFiJoin
    /// The network is in the list of networks macOS knows.
    func isKnown(_ name: String) -> Bool
}

/// The password of the hotspot. The real store is one item in the login
/// Keychain. The password is never in the settings, in a log, in the
/// state for the tests or in a recording.
protocol HotspotPasswordStoring {
    /// False when the password was not saved.
    func save(_ password: String) -> Bool
    /// Nil when there is none, or it cannot be read.
    func load() -> String?
    /// An item that was never there counts as removed.
    @discardableResult
    func remove() -> Bool
}
