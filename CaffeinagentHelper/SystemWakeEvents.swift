import Foundation
import IOKit.pwr_mgt
import os

// The list `pmset -g sched` prints, through the public calls of IOPMLib.h.
// Reading needs no root. Scheduling and cancelling do, and the helper has it.
//
// The owner name and the type are the constants of WakeAlarmCore in both
// calls, and macOS cancels only an event where the time, the name and the
// type all match. So nothing here can reach an event of macOS or of another
// app, whatever time is passed in. There is no call for "cancel all".
struct SystemWakeEvents: WakeEventStoring {
    private let log = Logger(subsystem: SleepFlagHelper.label, category: "SystemWakeEvents")

    // powerd gives an empty array for an empty list. So no array means
    // the list could not be read, and that is nil here: WakeAlarmCore
    // must not take it for "no alarm of ours".
    func events() -> [WakeEvent]? {
        guard let list = IOPMCopyScheduledPowerEvents()?.takeRetainedValue() as? [[String: Any]] else {
            log.error("IOPMCopyScheduledPowerEvents gave no list")
            return nil
        }
        return list.compactMap { entry in
            guard let date = entry[kIOPMPowerEventTimeKey] as? Date,
                  let owner = entry[kIOPMPowerEventAppNameKey] as? String,
                  let type = entry[kIOPMPowerEventTypeKey] as? String else { return nil }
            return WakeEvent(date: date, owner: owner, type: type)
        }
    }

    func schedule(at date: Date) -> Bool {
        let result = IOPMSchedulePowerEvent(date as CFDate, WakeAlarmCore.owner as CFString, WakeAlarmCore.eventType as CFString)
        if result != kIOReturnSuccess { log.error("IOPMSchedulePowerEvent failed: \(result)") }
        return result == kIOReturnSuccess
    }

    func cancel(at date: Date) -> Bool {
        let result = IOPMCancelScheduledPowerEvent(date as CFDate, WakeAlarmCore.owner as CFString, WakeAlarmCore.eventType as CFString)
        if result != kIOReturnSuccess { log.error("IOPMCancelScheduledPowerEvent failed: \(result)") }
        return result == kIOReturnSuccess
    }
}
