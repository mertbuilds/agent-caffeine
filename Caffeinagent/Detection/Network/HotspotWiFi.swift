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
    /// Only an open network has the name of the hotspot. It is never
    /// joined: anyone can give a network this name.
    case notSecure
    case other
}

/// A network a scan saw.
struct WiFiSighting: Equatable {
    /// The signal in dBm.
    var rssi: Int
    var channel: Int
}

/// How a network keeps others out, as far as a join asks.
enum WiFiSecurity: Equatable {
    /// No password: anyone can set up a network like it.
    case open
    /// One password for the network: WPA2 or WPA3 Personal. The hotspot
    /// of an iPhone is of this kind.
    case personal
    /// Anything else: WEP, the first WPA alone, or a network that asks
    /// for a user name.
    case other
}

/// One network of a scan.
struct WiFiSeen: Equatable {
    var name: String
    var sighting: WiFiSighting
    var security: WiFiSecurity
}

/// Which network of a scan the Mac may join. A name alone says nothing:
/// anyone can give an open network the name of the hotspot, with a
/// strong signal, so the kind of the network is asked too.
enum WiFiPick {
    /// The strongest network with the name of the hotspot that takes a
    /// password. `index` is its place in `seen`.
    static func hotspot(_ name: String, among seen: [WiFiSeen]) -> (index: Int?, scan: WiFiScan) {
        let named = seen.indices.filter { HotspotName.matches(seen[$0].name, name) }
        let safe = named.filter { seen[$0].security == .personal }
        if let best = safe.max(by: { seen[$0].sighting.rssi < seen[$1].sighting.rssi }) {
            return (best, .found(seen[best].sighting))
        }
        return (nil, named.contains { seen[$0].security == .open } ? .failed(.notSecure) : .notFound)
    }

    /// The strongest network that has the name of a network macOS knows
    /// to the letter, with no other spelling, and that takes a password.
    static func known(_ name: String, among seen: [WiFiSeen]) -> (index: Int?, scan: WiFiScan) {
        let safe = seen.indices.filter { seen[$0].name == name && seen[$0].security == .personal }
        guard let best = safe.max(by: { seen[$0].sighting.rssi < seen[$1].sighting.rssi }) else { return (nil, .notFound) }
        return (best, .found(seen[best].sighting))
    }
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
/// The name of the hotspot is matched as `HotspotName.matches` has it,
/// and the name of a network macOS knows to the letter. Nothing here
/// switches Wi-Fi on or off.
protocol WiFiAccess {
    /// Nil on a Mac with no Wi-Fi.
    func power() -> Bool?
    /// The name of the network the Mac is on. Nil when it is on none,
    /// and when macOS hides the name.
    func currentNetwork() -> String?
    /// A scan for the hotspot with this name. Only a network that takes
    /// a password is found: see `WiFiPick`.
    func scan(for name: String) -> WiFiScan
    /// A scan for a network macOS knows, by its name to the letter. It
    /// is found only when it takes a password, and is of the kind macOS
    /// knows it as.
    func scanKnown(_ name: String) -> WiFiScan
    /// Joins the network that the last scan found.
    /// - Parameter password: nil for a network macOS knows already: the
    ///   password of such a network is in the keychain of the system.
    func associate(to name: String, password: String?) -> WiFiJoin
    /// The kind of the network with this name, to the letter, in the
    /// list of networks macOS knows. Nil when it is not there.
    func knownSecurity(of name: String) -> WiFiSecurity?
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
