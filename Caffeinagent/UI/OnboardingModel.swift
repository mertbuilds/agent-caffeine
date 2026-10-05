import Foundation

enum OnboardingStep: Equatable {
    case welcome
    case hooks
    case lidClosed
    case done
}

/// The setup window of the first launch. It is offered once, every step
/// can be skipped, and the app works the same while it is open.
enum Onboarding {
    static let completedKey = "Onboarding.completed"

    static var isPending: Bool { !UserDefaults.standard.bool(forKey: completedKey) }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    /// The steps for this Mac. The hooks step needs an agent whose hooks
    /// are off or out of date, and the hook command in the Applications
    /// folder. The lid step needs a battery and the app in the Applications
    /// folder, and is left out when the helper is set up already.
    static func steps(hookStatuses: [HookStatus], hooksAvailable: Bool, canSetUpHelper: Bool, hasBattery: Bool, helperEnabled: Bool) -> [OnboardingStep] {
        var steps: [OnboardingStep] = [.welcome]
        if hooksAvailable, hookStatuses.contains(where: { $0 == .notInstalled || $0 == .outdated }) { steps.append(.hooks) }
        if canSetUpHelper, hasBattery, !helperEnabled { steps.append(.lidClosed) }
        steps.append(.done)
        return steps
    }
}
