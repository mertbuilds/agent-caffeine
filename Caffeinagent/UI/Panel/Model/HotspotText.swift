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

    static let hotspotTitle = "Join your iPhone hotspot (Beta)"
    static let hotspotSwitch = "Join your iPhone hotspot when Wi-Fi is lost"
    static let hotspotExplained = "When Wi-Fi is lost while an agent works, your Mac joins this hotspot. This uses the data and the battery of your phone."
    static let hotspotName = "Hotspot name"
    static let hotspotNamePrompt = "The name of your iPhone"
    static let hotspotPassword = "Password"
    static let hotspotPasswordSaved = "Saved in your Keychain"
    static let hotspotSave = "Save"
    static let hotspotOpenPrivacy = "Open Privacy settings"
    static let hotspotOpenWiFi = "Open Wi-Fi settings"
    static let hotspotHopBack = "Go back to your Wi-Fi when your Mac sees it again"
    static let hotspotHopBackExplained = "On the hotspot, your Mac looks for the Wi-Fi it lost every \(minutes(HotspotHop.backInterval)), and every \(minutes(HotspotHop.backIntervalInBag)) on battery with the lid closed."
    static let hotspotForgets = "The password is kept in your Keychain. When you switch this off, Agent Caffeine forgets the name and the password."

    private static func minutes(_ seconds: TimeInterval) -> String {
        HumaneDuration.counted(Int(seconds / 60), "minute")
    }

    /// What the feature cannot do. "Ask to join hotspots" has the choice
    /// Automatic from macOS 26 on: only macOS itself can wake the
    /// hotspot of an iPhone.
    static func hotspotLimit(offersAutomatic: Bool) -> String {
        offersAutomatic
            ? "Your iPhone shows its hotspot only for a short time. If your Mac does not find it, set Ask to join hotspots to Automatic in Wi-Fi settings."
            : "Your iPhone shows its hotspot only for a short time, so your Mac does not always find it."
    }

    static func hotspotAutoJoin(_ mode: HotspotAutoJoin) -> String {
        switch mode {
        case .automatic: return "Ask to join hotspots is set to Automatic"
        case .notAutomatic: return "Ask to join hotspots is not set to Automatic"
        }
    }

    /// The line next to "Save".
    static func hotspotSaveNote(_ note: HotspotSaveNote) -> String {
        switch note {
        case .incomplete: return "Type the name and the password of your hotspot"
        case .keychainFailed: return "Agent Caffeine could not save the password in your Keychain"
        case .saved(.allowed): return "Saved. Agent Caffeine can see the names of Wi-Fi networks."
        case .saved(.notNeeded): return "Saved"
        case .saved(.notAsked): return "Saved. Allow Location when macOS asks, so Agent Caffeine can find the hotspot by its name."
        case .saved(.denied): return "Saved. Location permission is off, so Agent Caffeine cannot find the hotspot."
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
            case .timeout: return HotspotStatusLine(text: "macOS gave no answer \(at(date))")
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
