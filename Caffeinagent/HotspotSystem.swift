import CoreLocation
import CoreWLAN
import Foundation
import Security

/// The Wi-Fi of this Mac through CoreWLAN, the public framework. Every
/// call blocks and is made off the main thread, and each has a time
/// limit: a call that macOS never answers ends as a failure, and no
/// other call starts while it hangs.
///
/// It runs in the app and not in the helper: from macOS 14 on, macOS
/// shows the names of Wi-Fi networks only to an app the user allowed in
/// Location Services, and a root daemon cannot be allowed.
///
/// It never switches Wi-Fi on or off, and it writes no name to a log.
final class SystemWiFi: WiFiAccess {
    static let scanTimeout: TimeInterval = 20
    static let joinTimeout: TimeInterval = 40
    private static let queue = DispatchQueue(label: "com.caffeinagent.app.wifi", qos: .utility, attributes: .concurrent)

    private let lock = NSLock()
    private var busy = false
    /// The network of the last scan that found one. A join needs it:
    /// CoreWLAN joins what a scan gave, not a name.
    private var found: (network: CWNetwork, exact: Bool)?
    private var lastError: String?

    /// The domain and the code of the last error of CoreWLAN, with no
    /// text of macOS: that text can hold a network name. For the probe.
    var lastErrorCode: String? {
        lock.lock()
        defer { lock.unlock() }
        return lastError
    }

    private var interface: CWInterface? { CWWiFiClient.shared().interface() }

    func power() -> Bool? {
        interface?.powerOn()
    }

    func currentNetwork() -> String? {
        interface?.ssid()
    }

    func scan(for name: String) -> WiFiScan {
        // macOS looks for the exact bytes, so each spelling of the
        // apostrophe gets a scan of its own.
        scan(names: HotspotName.spellings(of: name), exact: false, keep: { _ in true }, pick: { WiFiPick.hotspot(name, among: $0) })
    }

    func scanKnown(_ name: String) -> WiFiScan {
        guard let profile = profile(named: name) else { return .notFound }
        let security = profile.security
        return scan(names: [name], exact: true, keep: { $0.supportsSecurity(security) }, pick: { WiFiPick.known(name, among: $0) })
    }

    /// - Parameters:
    ///   - exact: the network that is found has one of `names` to the
    ///     letter. `associate` asks for the same then.
    ///   - keep: false for a network that is not looked at.
    private func scan(
        names: [String], exact: Bool, keep: @escaping (CWNetwork) -> Bool, pick: @escaping ([WiFiSeen]) -> (index: Int?, scan: WiFiScan)
    ) -> WiFiScan {
        guard let interface else { return .failed(.noWiFi) }
        let result: WiFiScan? = timed(Self.scanTimeout) { [self] in
            var hidden = false
            var open = false
            for name in names {
                do {
                    let networks = Array(try interface.scanForNetworks(withSSID: Data(name.utf8)))
                    let named = networks.filter { $0.ssid != nil && keep($0) }
                    let seen = named.map { network in
                        WiFiSeen(
                            name: network.ssid ?? "",
                            sighting: WiFiSighting(rssi: network.rssiValue, channel: network.wlanChannel?.channelNumber ?? 0),
                            security: Self.security(of: network)
                        )
                    }
                    let found = pick(seen)
                    if let index = found.index { remember(named[index], exact: exact) }
                    switch found.scan {
                    case .found: return found.scan
                    case .failed: open = true
                    case .notFound: break
                    }
                    // A network with no name: macOS hides it. It is never
                    // joined, because nothing says that it is the hotspot.
                    if networks.contains(where: { $0.ssid == nil }) { hidden = true }
                } catch {
                    return .failed(failure(of: error, joining: false))
                }
            }
            if open { return .failed(.notSecure) }
            return hidden ? .failed(.noPermission) : .notFound
        }
        return result ?? .failed(.timeout)
    }

    func associate(to name: String, password: String?) -> WiFiJoin {
        guard let interface else { return .failed(.noWiFi) }
        lock.lock()
        let found = found
        lock.unlock()
        guard let found, let ssid = found.network.ssid, found.exact ? ssid == name : HotspotName.matches(ssid, name) else { return .failed(.other) }
        let network = found.network
        let result: WiFiJoin? = timed(Self.joinTimeout) { [self] in
            do {
                try interface.associate(to: network, password: password)
                return .joined
            } catch {
                return .failed(failure(of: error, joining: true))
            }
        }
        return result ?? .failed(.timeout)
    }

    func knownSecurity(of name: String) -> WiFiSecurity? {
        guard let profile = profile(named: name) else { return nil }
        switch profile.security {
        case .none: return .open
        case .wpa2Personal, .wpaPersonalMixed, .wpa3Personal, .wpa3Transition: return .personal
        default: return .other
        }
    }

    /// The network macOS knows by this name, to the letter.
    private func profile(named name: String) -> CWNetworkProfile? {
        let profiles = interface?.configuration()?.networkProfiles.array as? [CWNetworkProfile] ?? []
        return profiles.first { $0.ssid == name }
    }

    /// What macOS says a network takes. An open network is open even
    /// when it says more.
    private static func security(of network: CWNetwork) -> WiFiSecurity {
        if network.supportsSecurity(.none) { return .open }
        let personal: [CWSecurity] = [.wpa2Personal, .wpaPersonalMixed, .wpa3Personal, .wpa3Transition]
        return personal.contains { network.supportsSecurity($0) } ? .personal : .other
    }

    private func remember(_ network: CWNetwork, exact: Bool) {
        lock.lock()
        found = (network, exact)
        lock.unlock()
    }

    /// Which error of CoreWLAN a refused password gives is not written
    /// down by Apple. These three are the ones of the key exchange.
    private func failure(of error: Error, joining: Bool) -> HopFailure {
        let error = error as NSError
        lock.lock()
        lastError = "\(error.domain) \(error.code)"
        lock.unlock()
        guard error.domain == CWErrorDomain else { return .other }
        switch error.code {
        case CWErr.cwInvalidPMKErr.rawValue, CWErr.cwSupplicantTimeoutErr.rawValue, CWErr.cwChallengeFailureErr.rawValue:
            return joining ? .wrongPassword : .other
        case CWErr.cwOperationNotPermittedErr.rawValue: return .noPermission
        case CWErr.cwTimeoutErr.rawValue: return .timeout
        default: return .other
        }
    }

    /// Nil when the time ran out, and when an earlier call still hangs.
    private func timed<Value>(_ seconds: TimeInterval, _ work: @escaping () -> Value) -> Value? {
        lock.lock()
        guard !busy else {
            lock.unlock()
            return nil
        }
        busy = true
        lock.unlock()
        let done = DispatchSemaphore(value: 0)
        var value: Value?
        Self.queue.async { [self] in
            let result = work()
            lock.lock()
            value = result
            busy = false
            lock.unlock()
            done.signal()
        }
        guard done.wait(timeout: .now() + seconds) == .success else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// The password of the hotspot as one generic password item in the login
/// Keychain of the user. The release build is signed with one Developer
/// ID for every version, so macOS lets each version read the item with
/// no question.
struct KeychainHotspotPassword: HotspotPasswordStoring {
    // A Debug build is signed ad hoc, and macOS asks before it reads the
    // item of another build. It keeps an item of its own.
    #if DEBUG
    private static let service = "com.caffeinagent.app.hotspot.debug"
    #else
    private static let service = "com.caffeinagent.app.hotspot"
    #endif
    private static let account = "hotspot"

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    func save(_ password: String) -> Bool {
        let data = Data(password.utf8)
        let update = SecItemUpdate(itemQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var add = itemQuery
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "Agent Caffeine hotspot password"
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    func load() -> String? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func remove() -> Bool {
        let status = SecItemDelete(itemQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// Location Services of macOS, for the names of Wi-Fi networks alone.
/// No location is asked for, read or kept: the manager never starts.
///
/// Nothing of CoreLocation is touched before the user switches the
/// feature on, and macOS is asked only by `ask`.
final class SystemLocation: NSObject, LocationAsking, CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private var waiting: [(LocationPermission) -> Void] = []

    /// Made on the main thread, where its delegate is called.
    private func made() -> CLLocationManager {
        if let manager { return manager }
        let made = CLLocationManager()
        made.delegate = self
        manager = made
        return made
    }

    var permission: LocationPermission {
        guard #available(macOS 14, *) else { return .notNeeded }
        switch made().authorizationStatus {
        case .notDetermined: return .notAsked
        case .denied, .restricted: return .denied
        default: return .allowed
        }
    }

    func ask(_ answered: @escaping (LocationPermission) -> Void) {
        let now = permission
        guard now == .notAsked else { return answered(now) }
        waiting.append(answered)
        made().requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let now = permission
        guard now != .notAsked else { return }
        let answered = waiting
        waiting = []
        answered.forEach { $0(now) }
    }
}

/// What the feature reads of the settings of macOS, and the panes of
/// System Settings it opens.
enum HotspotSystemSettings {
    /// Everyone on the Mac can read this file. Only the key
    /// `HotspotAutoJoin.key` is taken from it.
    private static let wifiPreferences = "/Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist"

    static func autoJoin() -> HotspotAutoJoin? {
        HotspotAutoJoin.read(from: NSDictionary(contentsOfFile: wifiPreferences) as? [String: Any])
    }

    /// "Ask to join hotspots" has the choice Automatic from macOS 26 on.
    static var offersAutomatic: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    static let locationPrivacy = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
    static let wifi = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")
}
