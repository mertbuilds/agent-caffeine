import Foundation

/// What the user chose for "Join your iPhone hotspot". Off, with no
/// hotspot, until the user says otherwise.
///
/// The name of the hotspot is here because a scan needs it. It is
/// private like every network name: it is shown in Settings and goes
/// nowhere else. The password is not here: see `HotspotPasswordStoring`.
struct HotspotSettings: Codable, Equatable {
    /// The switch of the feature.
    var on = false
    var name: String?
    /// A password is in the Keychain. The Keychain itself is read only
    /// for a join.
    var passwordSaved = false
    /// Go back to the Wi-Fi that was lost when it is seen again.
    var hopBack = true
    /// How often the user saved. See `HotspotHop.Input.saves`.
    var saves = 0

    init() {}

    /// A name and a password are saved.
    var isSetUp: Bool {
        HotspotName.cleaned(name) != nil && passwordSaved
    }

    private enum CodingKeys: String, CodingKey {
        case on, name, passwordSaved, hopBack, saves
    }

    /// A key that is missing or of the wrong type keeps its default.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = HotspotSettings()
        func value<Value: Decodable>(_ key: CodingKeys, _ fallback: Value) -> Value {
            (try? container.decodeIfPresent(Value.self, forKey: key)) ?? fallback
        }
        on = value(.on, defaults.on)
        name = HotspotName.cleaned(value(.name, defaults.name))
        passwordSaved = value(.passwordSaved, defaults.passwordSaved)
        hopBack = value(.hopBack, defaults.hopBack)
        saves = value(.saves, defaults.saves)
    }
}

/// The settings of the feature in UserDefaults, as one JSON value.
enum HotspotSettingsStore {
    static let key = "HotspotSettings"

    /// Settings that cannot be read give the defaults: the feature off.
    static func load(from defaults: UserDefaults) -> HotspotSettings {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(HotspotSettings.self, from: $0) } ?? HotspotSettings()
    }

    static func save(_ settings: HotspotSettings, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Whether macOS shows the names of Wi-Fi networks to Agent Caffeine.
/// From macOS 14 on that needs Location Services. Agent Caffeine reads
/// no location and keeps none.
enum LocationPermission: Equatable {
    case notAsked
    case allowed
    /// The user said no, or Location Services is off for the whole Mac.
    case denied
    /// macOS 13 shows the names without it.
    case notNeeded
}

/// The question of macOS about Location Services. It is asked only when
/// the user saves a hotspot, never at launch.
protocol LocationAsking: AnyObject {
    var permission: LocationPermission { get }
    /// Asks once. A permission that has an answer already comes back at
    /// once. The answer comes on the main thread.
    func ask(_ answered: @escaping (LocationPermission) -> Void)
}

/// "Ask to join hotspots" of the Wi-Fi settings of macOS. With
/// "Automatic", macOS wakes the hotspot of an iPhone by itself.
enum HotspotAutoJoin: Equatable {
    case automatic
    case notAutomatic

    static let key = "AutoHotspotMode"

    /// - Parameter preferences: the settings of the Wi-Fi of macOS. Nil
    ///   comes back when the key is not there: this macOS has no such
    ///   choice, or keeps it elsewhere.
    static func read(from preferences: [String: Any]?) -> HotspotAutoJoin? {
        guard let mode = preferences?[key] as? String else { return nil }
        return mode == "Automatic" ? .automatic : .notAutomatic
    }
}
