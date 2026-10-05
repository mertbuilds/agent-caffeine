import Foundation
import IOKit.pwr_mgt
import os

@MainActor
final class PowerKeeper {
    private var assertionIDs: [IOPMAssertionID] = []
    private var isHeld = false
    private let log = Logger(subsystem: "com.caffeinagent.app", category: "PowerKeeper")

    var held: Bool { isHeld }

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

    func acquire(reason: String) {
        guard !isHeld else { return }
        for type in Self.assertionTypes {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &id
            )
            if result == kIOReturnSuccess {
                assertionIDs.append(id)
            } else {
                log.error("IOPMAssertionCreateWithName(\(type, privacy: .public)) failed: \(result)")
            }
        }
        isHeld = !assertionIDs.isEmpty
        if isHeld {
            log.info("acquired power assertions: \(reason, privacy: .public)")
        }
    }

    func release() {
        guard isHeld else { return }
        for id in assertionIDs {
            let result = IOPMAssertionRelease(id)
            if result != kIOReturnSuccess {
                log.error("IOPMAssertionRelease failed: \(result)")
            }
        }
        assertionIDs.removeAll()
        isHeld = false
        log.info("released power assertions")
    }
}
