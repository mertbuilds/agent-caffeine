import Foundation
import IOKit.pwr_mgt
import os

/// The power assertions, so the smoke test can run the app without them.
@MainActor
protocol PowerHolding: AnyObject {
    var held: Bool { get }
    func hold(reason: String)
    func release()
}

@MainActor
final class PowerKeeper: PowerHolding {
    /// The assertions end on their own after this long, so an app that
    /// hangs cannot keep the Mac awake for good. Every `hold` starts the
    /// time again, and the engine decides every few seconds. Checked on
    /// macOS 26.7: setting the timeout again restarts it, and an assertion
    /// that timed out refuses the call.
    static let timeout: TimeInterval = 120

    private var assertionIDs: [IOPMAssertionID] = []
    private var reason = ""
    private let log = Logger(subsystem: "com.caffeinagent.app", category: "PowerKeeper")

    var held: Bool { !assertionIDs.isEmpty }

    // PreventUserIdleSystemSleep is the assertion that actually defeats the
    // idle-sleep timer on both AC and battery, the same one `caffeinate -i`
    // holds. PreventSystemSleep alone (the pre-0.2.3 behavior) is honored only
    // on AC and does NOT stop the user-idle timer, so a plugged-in mac still
    // slept once the agent went quiet. We hold both: the idle assertion keeps
    // the mac awake everywhere, and PreventSystemSleep additionally covers the
    // lid-closed-on-AC case.
    private static let assertionTypes = [
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionTypePreventSystemSleep,
    ]

    /// Takes the assertions, or keeps them for another `timeout` seconds.
    /// `reason` is what `pmset -g assertions` shows.
    func hold(reason: String) {
        if held, extend(reason: reason) { return }
        dropAssertions()
        for type in Self.assertionTypes {
            var id = IOPMAssertionID(0)
            let properties: [String: Any] = [
                kIOPMAssertionTypeKey: type,
                kIOPMAssertionNameKey: reason,
                kIOPMAssertionLevelKey: kIOPMAssertionLevelOn,
                kIOPMAssertionTimeoutKey: Self.timeout,
                kIOPMAssertionTimeoutActionKey: kIOPMAssertionTimeoutActionRelease,
            ]
            let result = IOPMAssertionCreateWithProperties(properties as CFDictionary, &id)
            if result == kIOReturnSuccess {
                assertionIDs.append(id)
            } else {
                log.error("IOPMAssertionCreateWithProperties(\(type, privacy: .public)) failed: \(result)")
            }
        }
        self.reason = reason
        if held {
            log.info("acquired power assertions: \(reason, privacy: .public)")
        }
    }

    func release() {
        guard held else { return }
        dropAssertions()
        log.info("released power assertions")
    }

    /// False when an assertion is gone, which is the case after a timeout.
    private func extend(reason: String) -> Bool {
        for id in assertionIDs {
            guard IOPMAssertionSetProperty(id, kIOPMAssertionTimeoutKey as CFString, Self.timeout as CFNumber) == kIOReturnSuccess else {
                return false
            }
            if reason != self.reason {
                IOPMAssertionSetProperty(id, kIOPMAssertionNameKey as CFString, reason as CFString)
            }
        }
        self.reason = reason
        return true
    }

    /// An assertion that timed out is already released, and releasing it
    /// again fails with no harm.
    private func dropAssertions() {
        for id in assertionIDs { IOPMAssertionRelease(id) }
        assertionIDs.removeAll()
    }
}
