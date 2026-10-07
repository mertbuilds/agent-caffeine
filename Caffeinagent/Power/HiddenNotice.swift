import Foundation

/// What only the menu tells the user: agent caffeine cannot do its work.
/// With the icon hidden nobody sees the menu, so a notification says it.
enum HiddenNotice: Equatable {
    /// The sleep flag is on and the helper was switched off in Login Items.
    case helperSwitchedOff
    /// The helper is enabled and gives no answer, so the lid closed on
    /// battery puts the Mac to sleep.
    case helperNotResponding
    case licenseExpired(ExpiredReason)

    var notificationText: String {
        switch self {
        case .helperSwitchedOff: return "Your Mac cannot sleep. Allow agent caffeine again in System Settings > General > Login Items."
        case .helperNotResponding: return PanelText.helperNotResponding
        case .licenseExpired(.trialOver): return "agent caffeine cannot keep your Mac awake because your trial has ended"
        case .licenseExpired(.unverified): return "agent caffeine cannot keep your Mac awake because your license was not checked for 30 days"
        case .licenseExpired(.activationRemoved): return "agent caffeine cannot keep your Mac awake because this Mac is no longer activated"
        }
    }

    /// One at a time, in the order of the menu: the helper comes first.
    /// The end of the trial has a notification of its own, with the icon
    /// shown too. See `TrialNotice`.
    static func current(flagLeftOn: Bool, helperNotResponding: Bool, entitlement: Entitlement) -> HiddenNotice? {
        if flagLeftOn { return .helperSwitchedOff }
        if helperNotResponding { return .helperNotResponding }
        if case .expired(let reason) = entitlement, reason != .trialOver { return .licenseExpired(reason) }
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
