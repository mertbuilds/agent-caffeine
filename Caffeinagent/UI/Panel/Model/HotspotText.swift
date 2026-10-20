import Foundation

/// The status line of "Join your iPhone hotspot" in Settings.
struct HotspotStatusLine: Equatable {
    var text: String
    /// The line has the button that opens Location Services.
    var opensPrivacy = false
}

/// Every line of "Join your iPhone hotspot", in Settings and in the
/// menu. The rules of `PanelText` count here too: plain words, a label
/// on one line has no period, and a time is a time of day on the clock
/// of the user.
///
/// No line names a network: the name of the hotspot is shown in its
/// field in Settings and nowhere else.
extension PanelText {
    // MARK: Settings

    static let hotspotTitle = "iPhone hotspot (Beta)"
    static let hotspotSwitch = "Join your iPhone hotspot when Wi-Fi is lost"
    static let hotspotExplained = "Uses the data and battery of your phone"
    static let hotspotInfo = "Only while an agent works. Your Mac stays on the hotspot until you change the network or it goes back to your Wi-Fi. If you leave the hotspot, your Mac does not join it again by itself. When you switch this off, Agent Caffeine forgets the name and the password."
    static let hotspotName = "Hotspot name"
    static let hotspotNamePrompt = "Name of your iPhone"
    static let hotspotPassword = "Password"
    static let hotspotPasswordSaved = "Saved in your Keychain"
    static let hotspotSave = "Save"
    static let hotspotOpenPrivacy = "Open Privacy settings"
    static let hotspotOpenWiFi = "Open Wi-Fi settings"
    static let hotspotHopBack = "Go back to your Wi-Fi when it returns"
    static let hotspotHopBackExplained = "Your Mac looks for the lost Wi-Fi every \(minutes(HotspotHop.backInterval)), and every \(minutes(HotspotHop.backIntervalInBag)) on battery with the lid closed. It goes back after a good signal 2 times in a row. It never goes to an open network or to one that asks for a user name. This works only when Agent Caffeine joined the hotspot."

    private static func minutes(_ seconds: TimeInterval) -> String {
        HumaneDuration.counted(Int(seconds / 60), "minute")
    }

    /// The row of "Ask to join hotspots" of macOS, with its value.
    static let hotspotAutoJoinTitle = "Ask to join hotspots"

    /// What the feature cannot do. "Ask to join hotspots" has the choice
    /// Automatic from macOS 26 on: only macOS itself can wake the
    /// hotspot of an iPhone.
    static func hotspotLimit(offersAutomatic: Bool) -> String {
        offersAutomatic
            ? "Your iPhone shows its hotspot only for a short time. With Automatic, your Mac finds it more often."
            : "Your iPhone shows its hotspot only for a short time"
    }

    static func hotspotAutoJoin(_ mode: HotspotAutoJoin) -> String {
        switch mode {
        case .automatic: return "Automatic"
        case .notAutomatic: return "Not Automatic"
        }
    }

    /// The line next to "Save".
    static func hotspotSaveNote(_ note: HotspotSaveNote) -> String {
        switch note {
        case .incomplete: return "Type the name and the password"
        case .keychainFailed: return "Could not save the password in your Keychain"
        case .removeFailed: return "Agent Caffeine could not remove the password from your Keychain. Try again."
        case .saved(.allowed), .saved(.notNeeded): return "Saved"
        case .saved(.notAsked): return "Saved. Allow Location when macOS asks."
        case .saved(.denied): return "Saved, but Location is off, so your Mac cannot find the hotspot."
        }
    }

    /// What the last try came to. Nil while there is nothing to say.
    static func hotspotStatus(_ view: HotspotView, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> HotspotStatusLine? {
        guard view.settings.on, view.settings.isSetUp else { return nil }
        let noPermission = HotspotStatusLine(text: "Location permission is off: open Privacy settings", opensPrivacy: true)
        if view.permission == .denied { return noPermission }
        func at(_ date: Date) -> String { "at \(jobEventTime(date, now: now, calendar: calendar, locale: locale))" }
        switch view.state {
        case .idle: return nil
        case .waiting: return HotspotStatusLine(text: "Wi-Fi is lost. Your Mac looks for the hotspot in a moment.")
        case .scanning: return HotspotStatusLine(text: "Looking for the hotspot")
        case .joined(let date): return HotspotStatusLine(text: "Joined \(at(date))")
        case .notFound(let date): return HotspotStatusLine(text: "Did not find the hotspot \(at(date))")
        case .hoppedBack(let date): return HotspotStatusLine(text: "Went back to your Wi-Fi \(at(date))")
        case .failed(let failure, let date):
            switch failure {
            case .noPermission: return noPermission
            case .wrongPassword: return HotspotStatusLine(text: "The hotspot refused the password \(at(date)). Save the password again.")
            case .wifiOff: return HotspotStatusLine(text: "Wi-Fi was off \(at(date))")
            case .noWiFi: return HotspotStatusLine(text: "This Mac has no Wi-Fi")
            case .noPassword: return HotspotStatusLine(text: "The password was not in your Keychain \(at(date)). Save it again.")
            case .keychainLocked: return HotspotStatusLine(text: "Your Keychain was locked \(at(date)), so your Mac did not join the hotspot")
            case .timeout: return HotspotStatusLine(text: "macOS gave no answer \(at(date))")
            case .notSecure: return HotspotStatusLine(text: "A network with this name is open, so your Mac did not join it")
            case .other: return HotspotStatusLine(text: "Could not join the hotspot \(at(date))")
            }
        }
    }

    // MARK: About

    static func hotspotRemoveStep(saved: Bool) -> String {
        saved ? "Forget your iPhone hotspot" : "No hotspot is saved"
    }

    static let hotspotRemoveHelp = "This removes the name of the hotspot from the settings and its password from your Keychain."

    // MARK: Menu

    /// The quiet line while the Mac is on the hotspot because Wi-Fi was
    /// lost.
    static func onHotspotSince(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        "On your iPhone hotspot since \(time(date, calendar: calendar, locale: locale))"
    }
}
