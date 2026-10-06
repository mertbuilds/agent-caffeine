import Foundation

/// What only the menu tells the user: agent caffeine cannot do its work.
/// With the icon hidden nobody sees the menu, so a notification says it.
enum HiddenNotice: Equatable {
    /// The sleep flag is on and the helper was switched off in Login Items.
    case helperSwitchedOff
    case licenseExpired(ExpiredReason)

    var notificationText: String {
        switch self {
        case .helperSwitchedOff: return "agent caffeine cannot let your Mac sleep because it was switched off in Login Items"
        case .licenseExpired(.trialOver): return "agent caffeine cannot keep your Mac awake because your trial has ended"
        case .licenseExpired(.unverified): return "agent caffeine cannot keep your Mac awake because your license was not checked for 30 days"
        case .licenseExpired(.activationRemoved): return "agent caffeine cannot keep your Mac awake because this Mac is no longer activated"
        }
    }

    /// One at a time, in the order of the menu: the helper comes first.
    static func current(flagLeftOn: Bool, entitlement: Entitlement) -> HiddenNotice? {
        if flagLeftOn { return .helperSwitchedOff }
        if case .expired(let reason) = entitlement { return .licenseExpired(reason) }
        return nil
    }

    /// The notice to tell the user about, nil for none. A notice is told
    /// once, when it begins, and only while the icon is hidden. One that
    /// began while the icon was shown is not told when the icon is hidden
    /// later: the menu showed it.
    static func toAnnounce(previous: HiddenNotice?, current: HiddenNotice?, iconHidden: Bool) -> HiddenNotice? {
        iconHidden && current != previous ? current : nil
    }
}
