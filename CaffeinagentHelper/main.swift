import Foundation

// Root daemon, registered by the app through SMAppService. launchd starts it
// at boot and when the app connects, and it stays resident: it sleeps on its
// queue and costs nothing while idle, and exiting would only add a race with
// an incoming connection. It leaves only when launchd stops it, or when the
// app retires it after an update, and clears a flag it owns and takes away
// its wake alarm on the way out.
//
// All it does for its client: set and clear SleepDisabled (two booleans), and
// keep one wake alarm (one time).
let service = HelperService(
    core: HelperCore(flag: SystemSleepFlag(), marker: MarkerFile(), timeout: SleepFlagHelper.heartbeatTimeout),
    alarm: WakeAlarmCore(store: SystemWakeEvents())
)
service.start()
service.exitOnTermination()

let listener = NSXPCListener(machServiceName: SleepFlagHelper.machServiceName)
// Only the app, signed by this team, gets a connection. Checked by the system
// against the caller's audit token on every connection.
listener.setConnectionCodeSigningRequirement(SleepFlagHelper.requirement(identifier: SleepFlagHelper.appBundleID))
listener.delegate = service
listener.resume()
dispatchMain()
