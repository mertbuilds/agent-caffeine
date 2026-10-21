import Foundation

/// The detection settings in UserDefaults, as one JSON value.
enum DetectionSettingsStore {
    static let key = "DetectionSettings"
    /// The name list of the builds before the catalog, and the default
    /// names those builds knew.
    static let legacyAllowlistKey = "ProcessWatcher.allowlist"
    static let legacyKnownDefaultsKey = "ProcessWatcher.knownDefaults"
    /// Set at the first load of a build that has this. Any saved Tink became
    /// Glass then, also one picked on purpose, since the two cannot be told
    /// apart. A sound picked after that is kept, Tink too.
    static let glassChimeKey = "DetectionSettings.glassChimeOnce"

    /// Settings that cannot be read give the defaults. The old name list is
    /// carried over once, then its keys are removed. A saved Tink becomes
    /// Glass once.
    static func load(from defaults: UserDefaults, catalog: AgentCatalog = .standard) -> DetectionSettings {
        var settings = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(DetectionSettings.self, from: $0) }
        if settings == nil, let allowlist = defaults.array(forKey: legacyAllowlistKey) as? [String] {
            let migrated = migrated(
                allowlist: allowlist, knownDefaults: defaults.array(forKey: legacyKnownDefaultsKey) as? [String], catalog: catalog
            )
            save(migrated, to: defaults)
            settings = migrated
        }
        defaults.removeObject(forKey: legacyAllowlistKey)
        defaults.removeObject(forKey: legacyKnownDefaultsKey)
        if !defaults.bool(forKey: glassChimeKey) {
            if settings?.lidChimeSound == .tink {
                settings?.lidChimeSound = .glass
                settings.map { save($0, to: defaults) }
            }
            defaults.set(true, forKey: glassChimeKey)
        }
        return settings ?? DetectionSettings()
    }

    static func save(_ settings: DetectionSettings, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }

    /// A name the catalog covers needs no entry, and any other name becomes
    /// a user name. A catalog agent that the old build offered and the user
    /// took off the list stays off: it gets the rule `.ignore`. Claude Code
    /// is left out, because the old build also found it without the list.
    static func migrated(allowlist: [String], knownDefaults: [String]?, catalog: AgentCatalog = .standard) -> DetectionSettings {
        var settings = DetectionSettings()
        let catalogNames = catalog.cliNames
        for name in allowlist where !catalogNames.contains(name.lowercased()) && !settings.userAgentNames.contains(name) {
            settings.userAgentNames.append(name)
        }
        let kept = Set(allowlist.map { $0.lowercased() })
        let offered = Set((knownDefaults ?? []).map { $0.lowercased() })
        for definition in catalog.definitions where definition.kind == .cli && definition.id != "claude" {
            let names = definition.processNames
            if !names.isEmpty, names.allSatisfy(offered.contains), !names.contains(where: kept.contains) {
                settings.agentRules[definition.id] = .ignore
            }
        }
        return settings
    }
}
