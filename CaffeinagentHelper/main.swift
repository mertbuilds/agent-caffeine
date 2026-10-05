import Foundation

// Root daemon, registered by the app through SMAppService. launchd starts it
// at boot and when the app connects, and it stays resident: it sleeps on its
// queue and costs nothing while idle, and exiting would only add a race with
// an incoming connection.
let service = HelperService()
service.start()

let listener = NSXPCListener(machServiceName: SleepFlagHelper.machServiceName)
// Only the app, signed by this team, gets a connection. Checked by the system
// against the caller's audit token on every connection.
listener.setConnectionCodeSigningRequirement(SleepFlagHelper.requirement(identifier: SleepFlagHelper.appBundleID))
listener.delegate = service
listener.resume()
dispatchMain()
