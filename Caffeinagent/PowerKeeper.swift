import Foundation
import IOKit.pwr_mgt
import os

@MainActor
final class PowerKeeper {
    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var isHeld = false
    private let log = Logger(subsystem: "com.caffeinagent.app", category: "PowerKeeper")

    var held: Bool { isHeld }

    func acquire(reason: String) {
        guard !isHeld else { return }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        if result == kIOReturnSuccess {
            isHeld = true
            log.info("acquired power assertion: \(reason, privacy: .public)")
        } else {
            log.error("IOPMAssertionCreateWithName failed: \(result)")
        }
    }

    func release() {
        guard isHeld else { return }
        let result = IOPMAssertionRelease(assertionID)
        if result == kIOReturnSuccess {
            isHeld = false
            assertionID = IOPMAssertionID(0)
            log.info("released power assertion")
        } else {
            log.error("IOPMAssertionRelease failed: \(result)")
        }
    }
}
