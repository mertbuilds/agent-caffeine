import CoreLocation
import CoreWLAN
import Foundation
import LocalAuthentication
import Security

/// The Wi-Fi of this Mac through CoreWLAN, the public framework. Every
/// call blocks and is made off the main thread, and each has a time
/// limit (`TimedCalls`): a call that macOS never answers ends as a
/// failure, and no other call starts while it hangs.
///
/// It runs in the app and not in the helper: from macOS 14 on, macOS
/// shows the names of Wi-Fi networks only to an app the user allowed in
/// Location Services, and a root daemon cannot be allowed.
///
/// It never switches Wi-Fi on or off, and it writes no name to a log.
final class SystemWiFi: WiFiAccess {
    static let scanTimeout: TimeInterval = 20
    static let joinTimeout: TimeInterval = 40
    /// For a question macOS answers at once when all is well: is Wi-Fi
    /// on, which network is the Mac on, which networks does it know.
    static let readTimeout: TimeInterval = 5

    private let calls = TimedCalls(label: "com.caffeinagent.app.wifi")
    private let lock = NSLock()
    /// The network of the last scan that found one. A join needs it:
    /// CoreWLAN joins what a scan gave, not a name.
    private let found = FoundNetwork<(network: CWNetwork, exact: Bool)>()
    private var lastError: String?

    /// The domain and the code of the last error of CoreWLAN, with no
    /// text of macOS: that text can hold a network name. For the probe.
    var lastErrorCode: String? {
        lock.lock()
        defer { lock.unlock() }
        return lastError
    }

    /// Asked for inside each timed call: this can hang like any other
    /// call into CoreWLAN.
    private static var interface: CWInterface? { CWWiFiClient.shared().interface() }

    /// One question to the interface, with the time limit of a read.
    private func read<Value>(_ question: @escaping (CWInterface) -> Value) -> Result<Value, HopFailure> {
        let answer: Value?? = calls.run(Self.readTimeout) { Self.interface.map(question) }
        guard let answer else { return .failure(.timeout) }
        guard let value = answer else { return .failure(.noWiFi) }
        return .success(value)
    }

    func power() -> Result<Bool, HopFailure> {
        read { $0.powerOn() }
    }

    func currentNetwork() -> Result<String?, HopFailure> {
        read { $0.ssid() }
    }

    func scan(for name: String) -> WiFiScan {
        // macOS looks for the exact bytes, so each spelling of the
        // apostrophe gets a scan of its own.
        scan(names: HotspotName.spellings(of: name), exact: false, keep: { _ in true }, pick: { WiFiPick.hotspot(name, among: $0) })
    }

    func scanKnown(_ name: String) -> WiFiScan {
        let security: CWSecurity
        switch knownProfile(name) {
        case .failure(let failure): return .failed(failure)
        case .success(nil): return .notFound
        case .success(let known?): security = known
        }
        return scan(names: [name], exact: true, keep: { $0.supportsSecurity(security) }, pick: { WiFiPick.known(name, among: $0) })
    }

    /// - Parameters:
    ///   - exact: the network that is found has one of `names` to the
    ///     letter. `associate` asks for the same then.
    ///   - keep: false for a network that is not looked at.
    private func scan(
        names: [String], exact: Bool, keep: @escaping (CWNetwork) -> Bool, pick: @escaping ([WiFiSeen]) -> (index: Int?, scan: WiFiScan)
    ) -> WiFiScan {
        found.forget()
        let result: (scan: WiFiScan, network: CWNetwork?)? = calls.run(Self.scanTimeout) { [self] in
            guard let interface = Self.interface else { return (.failed(.noWiFi), nil) }
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
                    let picked = pick(seen)
                    switch picked.scan {
                    case .found: return (picked.scan, picked.index.map { named[$0] })
                    case .failed: open = true
                    case .notFound: break
                    }
                    // A network with no name: macOS hides it. It is never
                    // joined, because nothing says that it is the hotspot.
                    if networks.contains(where: { $0.ssid == nil }) { hidden = true }
                } catch {
                    return (.failed(failure(of: error, joining: false)), nil)
                }
            }
            if open { return (.failed(.notSecure), nil) }
            return (hidden ? .failed(.noPermission) : .notFound, nil)
        }
        // A scan that ended after its time limit keeps nothing.
        guard let result else { return .failed(.timeout) }
        if let network = result.network { found.keep((network, exact)) }
        return result.scan
    }

    func associate(to name: String, password: String?) -> WiFiJoin {
        guard let found = found.take(), let ssid = found.network.ssid, found.exact ? ssid == name : HotspotName.matches(ssid, name) else { return .failed(.other) }
        let network = found.network
        let result: WiFiJoin? = calls.run(Self.joinTimeout) { [self] in
            guard let interface = Self.interface else { return .failed(.noWiFi) }
            do {
                try interface.associate(to: network, password: password)
                return .joined
            } catch {
                return .failed(failure(of: error, joining: true))
            }
        }
        return result ?? .failed(.timeout)
    }

    func knownSecurity(of name: String) -> Result<WiFiSecurity?, HopFailure> {
        knownProfile(name).map { security in
            switch security {
            case nil: return nil
            case CWSecurity.none?: return .open
            case .wpa2Personal?, .wpaPersonalMixed?, .wpa3Personal?, .wpa3Transition?: return .personal
            default: return .other
            }
        }
    }

    /// What macOS knows the network with this name as, to the letter.
    /// Nil when macOS does not know it.
    private func knownProfile(_ name: String) -> Result<CWSecurity?, HopFailure> {
        read { interface in
            let profiles = interface.configuration()?.networkProfiles.array as? [CWNetworkProfile] ?? []
            return profiles.first { $0.ssid == name }?.security
        }
    }

    /// What macOS says a network takes. An open network is open even
    /// when it says more.
    private static func security(of network: CWNetwork) -> WiFiSecurity {
        if network.supportsSecurity(.none) { return .open }
        let personal: [CWSecurity] = [.wpa2Personal, .wpaPersonalMixed, .wpa3Personal, .wpa3Transition]
        return personal.contains { network.supportsSecurity($0) } ? .personal : .other
    }

    /// See `HopFailure.of(coreWLAN:joining:)`.
    private func failure(of error: Error, joining: Bool) -> HopFailure {
        let error = error as NSError
        lock.lock()
        lastError = "\(error.domain) \(error.code)"
        lock.unlock()
        guard error.domain == CWErrorDomain else { return .other }
        return HopFailure.of(coreWLAN: error.code, joining: joining)
    }
}

/// The password of the hotspot as one generic password item in the login
/// Keychain of the user. The release build is signed with one Developer
/// ID for every version, so macOS lets each version read the item with
/// no question.
///
/// A read is made for a join, often with the lid closed, when nobody
/// answers a window. A locked Keychain is not read: `isLocked` is asked
/// first, because macOS can show its window for an item of a Keychain
/// in a file, whatever the query says. The read has a time limit like
/// every call of the join. When macOS shows a window all the same, the
/// try fails with `timeout`, and so does each later one until the user
/// answered.
struct KeychainHotspotPassword: HotspotPasswordStoring {
    static let readTimeout: TimeInterval = 5
    private static let calls = TimedCalls(label: "com.caffeinagent.app.hotspot.keychain")

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

    /// A question that macOS did not answer in time counts as not
    /// locked: the read that follows fails with `timeout` then.
    func isLocked() -> Bool {
        Self.calls.run(Self.readTimeout) { (LoginKeychain.self as KeychainLockReading.Type).isLocked() } ?? false
    }

    func load() -> Result<String, HopFailure> {
        let query = itemQuery
        return Self.calls.run(Self.readTimeout) { Self.read(query) } ?? .failure(.timeout)
    }

    private static func read(_ item: [String: Any]) -> Result<String, HopFailure> {
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // For an item that macOS guards with Touch ID: the read fails in
        // place of a question. It does not stop the window of a locked
        // Keychain in a file. `isLocked` is there for that one.
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data, let password = String(data: data, encoding: .utf8) else { return .failure(.noPassword) }
            return .success(password)
        case errSecInteractionNotAllowed, errSecAuthFailed:
            return .failure(.keychainLocked)
        default:
            return .failure(.noPassword)
        }
    }

    @discardableResult
    func remove() -> Bool {
        let status = SecItemDelete(itemQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// Reached through this protocol alone, so the compiler gives no
/// warning for `SecKeychainGetStatus`. macOS has no newer call that says
/// whether a Keychain in a file is locked.
private protocol KeychainLockReading {
    static func isLocked() -> Bool
}

/// The Keychain a query with no Keychain named goes to: the login
/// Keychain of the user.
private enum LoginKeychain: KeychainLockReading {
    /// False when macOS does not say: the read, with its time limit,
    /// says more then.
    @available(macOS, deprecated: 10.10)
    static func isLocked() -> Bool {
        var status = SecKeychainStatus()
        guard SecKeychainGetStatus(nil, &status) == errSecSuccess else { return false }
        return status & kSecUnlockStateStatus == 0
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
