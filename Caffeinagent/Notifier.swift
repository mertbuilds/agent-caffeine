import AppKit
import Darwin
import UserNotifications

enum NotificationPermission: Equatable {
    case notAsked
    case allowed
    /// Switched off for agent caffeine in System Settings.
    case denied
}

/// What the aggregator sends agent notifications through. The smoke test
/// has none.
@MainActor
protocol AgentNotifying: AnyObject {
    /// Called on the main actor when the permission is read or asked for.
    var onPermission: ((NotificationPermission) -> Void)? { get set }
    func post(_ content: AgentNoticeContent)
    /// macOS asks the user the first time, and never again.
    func requestPermission()
    func readPermission()
    func openSystemSettings()
}

/// The notifications of the app: a safety stop, what the hidden icon
/// cannot show, and an agent that waits or finished.
final class Notifier: NSObject, AgentNotifying, UNUserNotificationCenterDelegate {
    @MainActor static let shared = Notifier()

    @MainActor var onPermission: ((NotificationPermission) -> Void)?
    private static let ownerKey = "ownerPid"

    @MainActor
    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Tells the user that agent caffeine stopped keeping the Mac awake,
    /// or cannot do its work. macOS asks for permission the first time.
    /// Without permission nothing is shown. A new notice replaces the one
    /// before it.
    static func post(_ text: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.body = text
            center.add(UNNotificationRequest(identifier: "safety-stop", content: content, trigger: nil))
        }
    }

    @MainActor
    func post(_ notice: AgentNoticeContent) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            self?.report(granted ? .allowed : .denied)
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.subtitle = notice.subtitle ?? ""
            content.body = notice.body ?? ""
            content.threadIdentifier = notice.thread
            content.sound = notice.sound ? .default : nil
            if let ownerPid = notice.ownerPid { content.userInfo = [Self.ownerKey: Int(ownerPid)] }
            center.add(UNNotificationRequest(identifier: notice.id, content: content, trigger: nil))
        }
    }

    @MainActor
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            self?.report(granted ? .allowed : .denied)
        }
    }

    @MainActor
    func readPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .notDetermined: self?.report(.notAsked)
            case .denied: self?.report(.denied)
            default: self?.report(.allowed)
            }
        }
    }

    @MainActor
    func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func report(_ permission: NotificationPermission) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.onPermission?(permission) } }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Also while Preferences is in front.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// A click brings the app the agent runs in to the front, when it
    /// still runs.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let pid = response.notification.request.content.userInfo[Self.ownerKey] as? Int,
           let app = NSRunningApplication(processIdentifier: pid_t(pid)), app.activationPolicy == .regular {
            app.activate(options: [])
        }
        completionHandler()
    }
}

extension AgentOwner {
    /// The apps with windows that run now.
    static func runningApps() -> Set<Int32> {
        Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier))
    }

    /// The app this process runs in, read from the process table.
    static func resolve(pid: Int32, apps: Set<Int32>) -> Int32? {
        find(from: pid, parent: parentPid(of:), isApp: apps.contains)
    }

    private static func parentPid(of pid: Int32) -> Int32? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var entry = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &entry, &size, nil, 0) == 0, size > 0, entry.kp_proc.p_pid == pid else { return nil }
        return entry.kp_eproc.e_ppid
    }

    /// The user touched the keyboard or the pointer within `activeWithin`.
    static func userIsActive() -> Bool {
        guard let any = CGEventType(rawValue: ~0) else { return false }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any) < activeWithin
    }
}
