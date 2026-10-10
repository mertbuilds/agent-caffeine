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

    // The call gives no array for an empty list, and also when it cannot
    // read it. Both are an empty list here: WakeAlarmCore reads the list
    // again after it scheduled, and reports an alarm it does not find.
    func events() -> [WakeEvent] {
        guard let list = IOPMCopyScheduledPowerEvents()?.takeRetainedValue() as? [[String: Any]] else { return [] }
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
