import Foundation
import IOKit.ps

extension SafetyInputs {
    static func current() -> SafetyInputs {
        SafetyInputs(
            batteryPercent: batteryPercent(),
            onBattery: PowerSource.isOnBattery(),
            thermalState: ProcessInfo.processInfo.thermalState
        )
    }

    private static func batteryPercent() -> Int? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return nil
        }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let type = info[kIOPSTransportTypeKey] as? String,
                  type == kIOPSInternalType,
                  let current = info[kIOPSCurrentCapacityKey] as? Int,
                  let max = info[kIOPSMaxCapacityKey] as? Int,
                  max > 0
            else { continue }
            return current * 100 / max
        }
        return nil
    }
}
