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
        _ action: HotspotHop.Action, wifi: WiFiAccess, password: () -> Result<String, HopFailure>, mayJoin: () -> Bool
    ) -> HotspotHop.Outcome {
        switch action {
        case .look:
            switch wifi.currentNetwork() {
            case .success(let name): return .network(name)
            case .failure(let failure): return .failed(failure)
            }
        case .join(let name):
            return join(name, wifi: wifi, password: password, mayJoin: mayJoin)
        case .back(let hotspot, let old, let seen):
            return back(from: hotspot, to: old, seen: seen, wifi: wifi)
        }
    }

    private static func join(
        _ name: String, wifi: WiFiAccess, password: () -> Result<String, HopFailure>, mayJoin: () -> Bool
    ) -> HotspotHop.Outcome {
        guard mayJoin() else { return .pathBack }
        switch wifi.power() {
        case .failure(let failure): return .failed(failure)
        // Agent Caffeine never switches Wi-Fi on.
        case .success(false): return .failed(.wifiOff)
        case .success(true): break
        }
        // On the hotspot with no path: a second join would only cut the
        // Mac off while the phone gives it an address. When macOS does
        // not say which network the Mac is on, nothing is joined either.
        switch wifi.currentNetwork() {
        case .failure(let failure): return .failed(failure)
        case .success(let current?) where HotspotName.matches(current, name): return .onHotspot
        case .success: break
        }
        let saved: String
        switch password() {
        case .failure(let failure): return .failed(failure)
        case .success(let read) where read.isEmpty: return .failed(.noPassword)
        case .success(let read): saved = read
        }
        switch wifi.scan(for: name) {
        case .notFound: return .notFound
        case .failed(let failure): return .failed(failure)
        case .found: break
        }
        // The scan took seconds. No join takes what it found.
        guard mayJoin() else {
            wifi.forgetFound()
            return .pathBack
        }
        switch wifi.associate(to: name, password: saved) {
        case .joined: return .joined
        case .failed(let failure): return .failed(failure)
        }
    }

    /// The way back is taken only to a network macOS knows as one with a
    /// password, so its password is with macOS, and only when a scan
    /// sees it now by the same name to the letter. An open network and a
    /// network that asks for a user name get no way back: anyone can set
    /// up an open network with that name. A weak signal is no way back,
    /// and the first look with a good signal joins nothing yet. A scan
    /// that failed is a failure, so it does not count as a look that
    /// did not see the network.
    private static func back(from hotspot: String, to old: String?, seen: Bool, wifi: WiFiAccess) -> HotspotHop.Outcome {
        switch wifi.currentNetwork() {
        // Nothing is known, so nothing changes.
        case .failure(let failure): return .failed(failure)
        case .success(let current?) where HotspotName.matches(current, hotspot): break
        case .success: return .leftHotspot
        }
        guard let old else { return .onHotspot }
        switch wifi.knownSecurity(of: old) {
        case .failure(let failure): return .failed(failure)
        case .success(.personal): break
        case .success: return .backFailed
        }
        // No join takes a network that is weak, or seen for the first time.
        switch wifi.scanKnown(old) {
        // A scan that did not run says nothing of the air.
        case .failed(let failure): return .failed(failure)
        case .found(let sighting) where sighting.rssi >= HotspotHop.backSignal: break
        case .found, .notFound:
            wifi.forgetFound()
            return .onHotspot
        }
        guard seen else {
            wifi.forgetFound()
            return .sawOld
        }
        switch wifi.associate(to: old, password: nil) {
        case .joined: return .wentBack
        case .failed: return .backFailed
        }
    }
}
