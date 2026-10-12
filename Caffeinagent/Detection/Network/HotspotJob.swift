import Foundation

/// Runs one action of `HotspotHop` against the Wi-Fi of the Mac. Each
/// call blocks for as long as the scan and the join take, so it runs off
/// the main thread.
enum HotspotJob {
    /// - Parameters:
    ///   - password: asked only for a join of the hotspot.
    ///   - mayJoin: asked right before the join of the hotspot. False
    ///     when the Mac has a way to the network by now, or the join is
    ///     not wanted any more: a network that works is never left for
    ///     the hotspot.
    static func run(
        _ action: HotspotHop.Action, wifi: WiFiAccess, password: () -> String?, mayJoin: () -> Bool
    ) -> HotspotHop.Outcome {
        switch action {
        case .look:
            return .network(wifi.currentNetwork())
        case .join(let name):
            return join(name, wifi: wifi, password: password, mayJoin: mayJoin)
        case .back(let hotspot, let old, let seen):
            return back(from: hotspot, to: old, seen: seen, wifi: wifi)
        }
    }

    private static func join(_ name: String, wifi: WiFiAccess, password: () -> String?, mayJoin: () -> Bool) -> HotspotHop.Outcome {
        guard mayJoin() else { return .pathBack }
        guard let power = wifi.power() else { return .failed(.noWiFi) }
        // Agent Caffeine never switches Wi-Fi on.
        guard power else { return .failed(.wifiOff) }
        guard let password = password(), !password.isEmpty else { return .failed(.noPassword) }
        switch wifi.scan(for: name) {
        case .notFound: return .notFound
        case .failed(let failure): return .failed(failure)
        case .found: break
        }
        // The scan took seconds.
        guard mayJoin() else { return .pathBack }
        switch wifi.associate(to: name, password: password) {
        case .joined: return .joined
        case .failed(let failure): return .failed(failure)
        }
    }

    /// The way back is taken only to a network macOS knows as one with a
    /// password, so its password is with macOS, and only when a scan
    /// sees it now by the same name to the letter. An open network and a
    /// network that asks for a user name get no way back: anyone can set
    /// up an open network with that name. A weak signal is no way back,
    /// and the first look with a good signal joins nothing yet.
    private static func back(from hotspot: String, to old: String?, seen: Bool, wifi: WiFiAccess) -> HotspotHop.Outcome {
        guard let current = wifi.currentNetwork(), HotspotName.matches(current, hotspot) else { return .leftHotspot }
        guard let old else { return .onHotspot }
        guard wifi.knownSecurity(of: old) == .personal else { return .backFailed }
        guard case .found(let sighting) = wifi.scanKnown(old), sighting.rssi >= HotspotHop.backSignal else { return .onHotspot }
        guard seen else { return .sawOld }
        switch wifi.associate(to: old, password: nil) {
        case .joined: return .wentBack
        case .failed: return .backFailed
        }
    }
}
