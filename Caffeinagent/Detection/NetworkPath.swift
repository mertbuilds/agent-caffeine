import Foundation
import Network

/// What macOS says about the way to the network, as plain values, so a
/// test can pass any path.
///
/// Agent Caffeine sends nothing to find this out. It only reads what
/// macOS already knows about its interfaces. So a Wi-Fi that is connected
/// with no internet behind it reads as online: only a request to a server
/// could tell, and the app makes none but the check for updates.
struct NetworkPath: Equatable {
    enum Kind: Equatable {
        case wifi
        case wired
        case cellular
        case loopback
        /// Anything else: a tunnel of a VPN, or a link macOS has no type for.
        case other
    }

    struct Interface: Equatable {
        var kind: Kind
        /// The name of macOS, such as "en0" or "utun3".
        var name: String
    }

    /// macOS says the default path can be used.
    var satisfied: Bool
    /// The interfaces the path can use.
    var interfaces: [Interface]

    /// The names of interfaces that are tunnels and carry nothing by
    /// themselves.
    static let tunnelPrefixes = ["utun", "ipsec", "ppp", "tun", "tap"]

    /// True when the path can be used and one of its interfaces reaches
    /// out of the Mac by itself. The loopback does not, and the tunnel of
    /// a VPN does not: a VPN can keep its tunnel as the default path after
    /// the Wi-Fi under it is gone. An interface of an unknown type that is
    /// no tunnel counts as a link, so a link that macOS has no type for
    /// never reads as offline.
    var isOnline: Bool {
        satisfied && interfaces.contains { interface in
            switch interface.kind {
            case .wifi, .wired, .cellular: return true
            case .loopback: return false
            case .other: return !Self.tunnelPrefixes.contains { interface.name.hasPrefix($0) }
            }
        }
    }
}

/// Whether the Mac has a way to the network right now.
protocol NetworkPathReading {
    /// Nil while macOS has not said yet. That counts as online.
    func path() -> NetworkPath?
}

/// `NWPathMonitor` of the Network framework. It watches the interfaces of
/// the Mac and makes no network request of its own.
final class SystemNetworkPath: NetworkPathReading {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var latest: NetworkPath?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let read = NetworkPath(
                satisfied: path.status == .satisfied,
                interfaces: path.availableInterfaces.map { NetworkPath.Interface(kind: Self.kind(of: $0.type), name: $0.name) }
            )
            guard let self else { return }
            self.lock.lock()
            self.latest = read
            self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "com.caffeinagent.app.network-path", qos: .utility))
    }

    deinit {
        monitor.cancel()
    }

    func path() -> NetworkPath? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    private static func kind(of type: NWInterface.InterfaceType) -> NetworkPath.Kind {
        switch type {
        case .wifi: return .wifi
        case .wiredEthernet: return .wired
        case .cellular: return .cellular
        case .loopback: return .loopback
        case .other: return .other
        @unknown default: return .other
        }
    }
}
