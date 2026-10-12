import AppKit
import Darwin
import Foundation

/// Measures what "Join your iPhone hotspot" can count on, with no window
/// and no menu bar app:
///
///     caffeinagent --hotspot-probe "<name>" [--join] [--seconds N]
///
/// Once per second it prints whether a scan for the name sees it, with
/// the signal and the channel, what macOS says about Location Services,
/// whether Wi-Fi is on, and whether the Mac has a way to the network.
/// This answers what nobody wrote down: whether an iPhone that sits idle
/// shows its hotspot to a scan, whether a scan works with the lid closed
/// and the screen locked, and what a scan gives without the permission.
///
/// Without `--join` it only reads. With `--join` it asks for the
/// password, which is not shown and not stored, and joins the hotspot
/// once, when a scan first finds it: the Mac leaves the network it is
/// on. An empty password tries the join with none, as for a network
/// macOS knows already.
///
/// It never switches Wi-Fi on or off, it asks macOS for no permission,
/// and it prints no network name but the one it was given.
enum HotspotProbe {
    @MainActor
    static func run(_ options: HotspotProbeOptions) -> Never {
        setvbuf(stdout, nil, _IOLBF, 0)
        // macOS shows network names only to a process that is an app.
        NSApplication.shared.setActivationPolicy(.accessory)
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "HH:mm:ss"
        let wifi = SystemWiFi()
        let location = SystemLocation()
        let path = SystemNetworkPath()

        print("# scan for \"\(options.name)\" for \(Int(options.seconds)) seconds\(options.join ? ", and join it once" : ", reading only")")
        var password: String?
        if options.join {
            print("# the Mac leaves the network it is on when the hotspot is joined")
            password = readPassword()
            print("# password: \(password == nil ? "none" : "given")")
        }
        print(["time", "found", "rssi", "channel", "location", "wifi", "path", "onHotspot"].joined(separator: "\t"))

        let end = Date().addingTimeInterval(options.seconds)
        var joinTried = false
        while Date() < end {
            let began = Date()
            let scan = wifi.scan(for: options.name)
            var found = "no", rssi = "", channel = ""
            switch scan {
            case .found(let sighting):
                (found, rssi, channel) = ("yes", "\(sighting.rssi)", "\(sighting.channel)")
            case .notFound:
                break
            case .failed(let failure):
                found = "failed:\(failure.rawValue)\(wifi.lastErrorCode.map { " (\($0))" } ?? "")"
            }
            let onHotspot = wifi.currentNetwork().map { HotspotName.matches($0, options.name) } ?? false
            print([
                clock.string(from: began), found, rssi, channel, word(location.permission), word(wifi.power()),
                word(path.path()), onHotspot ? "yes" : "no",
            ].joined(separator: "\t"))
            if options.join, !joinTried, case .found = scan {
                joinTried = true
                let started = Date()
                let join = wifi.associate(to: options.name, password: password)
                let took = String(format: "%.1f", Date().timeIntervalSince(started))
                switch join {
                case .joined:
                    print("# join: joined after \(took) seconds")
                case .failed(let failure):
                    print("# join: failed:\(failure.rawValue)\(wifi.lastErrorCode.map { " (\($0))" } ?? "") after \(took) seconds")
                }
            }
            // One row per second at most. A scan can take longer.
            let left = 1 - Date().timeIntervalSince(began)
            if left > 0 { Thread.sleep(forTimeInterval: left) }
        }
        if options.join, !joinTried { print("# join: not tried, no scan found the hotspot") }
        exit(0)
    }

    private static func word(_ permission: LocationPermission) -> String {
        switch permission {
        case .notAsked: return "notAsked"
        case .allowed: return "allowed"
        case .denied: return "denied"
        case .notNeeded: return "notNeeded"
        }
    }

    private static func word(_ power: Bool?) -> String {
        power.map { $0 ? "on" : "off" } ?? "none"
    }

    private static func word(_ path: NetworkPath?) -> String {
        path.map { $0.isOnline ? "online" : "offline" } ?? "unknown"
    }

    /// One line from the terminal, not shown while it is typed. Nil for
    /// an empty line. The password stays in this process and is written
    /// nowhere.
    private static func readPassword() -> String? {
        FileHandle.standardError.write(Data("Password of the hotspot (not shown, not stored, empty for none): ".utf8))
        let terminal = isatty(STDIN_FILENO) == 1
        var before = termios()
        if terminal {
            tcgetattr(STDIN_FILENO, &before)
            var silent = before
            silent.c_lflag &= ~tcflag_t(ECHO)
            tcsetattr(STDIN_FILENO, TCSANOW, &silent)
        }
        let line = readLine(strippingNewline: true)
        if terminal {
            tcsetattr(STDIN_FILENO, TCSANOW, &before)
            FileHandle.standardError.write(Data("\n".utf8))
        }
        return (line?.isEmpty ?? true) ? nil : line
    }
}
