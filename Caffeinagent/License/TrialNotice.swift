import Foundation

/// The two notifications about the trial. Like the ones about a safety
/// stop they have no switch: nobody should find out from a Mac that slept.
enum TrialNotice: String, CaseIterable {
    /// The last 24 hours of the trial began.
    case endsSoon
    case ended

    /// The notice to tell the user about, nil for none. Each is told
    /// once, and the caller remembers which.
    static func due(entitlement: Entitlement, told: Set<TrialNotice>) -> TrialNotice? {
        switch entitlement {
        case .trial(let daysLeft) where daysLeft <= 1: return told.contains(.endsSoon) ? nil : .endsSoon
        case .expired(.trialOver), .expired(.updatesEnded): return told.contains(.ended) ? nil : .ended
        case .trial, .licensed, .expired: return nil
        }
    }

    /// For the log.
    var logLine: String { "trial \(rawValue) posted" }
}

/// Which trial notices were told, in UserDefaults, so a restart of the
/// app tells none of them again.
enum TrialNoticeStore {
    /// Not "TrialNotice.told", which the paid builds up to 1.0.3 wrote: the
    /// new trial tells both again.
    static let key = "TrialNotice.told2"

    static func load(from defaults: UserDefaults) -> Set<TrialNotice> {
        Set((defaults.stringArray(forKey: key) ?? []).compactMap(TrialNotice.init(rawValue:)))
    }

    static func save(_ told: Set<TrialNotice>, to defaults: UserDefaults) {
        defaults.set(told.map(\.rawValue).sorted(), forKey: key)
    }
}
