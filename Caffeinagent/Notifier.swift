import AppKit
import Darwin
import os
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
    /// Called on the main actor for each posted notification, with its id.
    var onDelivery: ((String, AgentNoticeDelivery) -> Void)? { get set }
    /// Called on the main actor for a click on a notification about one agent.
    var onOpen: ((AgentNoticeTarget) -> Void)? { get set }
    func post(_ content: AgentNoticeContent)
    /// macOS asks the user the first time, and never again.
    func requestPermission()
    func readPermission()
    func openSystemSettings()
}

/// What System Settings says about the notifications of agent caffeine.
struct NotificationAllowance: Equatable {
    enum Status: String {
        case notDetermined, denied, authorized, provisional
    }

    var status: Status
    /// False with the style "None".
    var banners = true
    var sound = true
    var inNotificationCenter = true

    var permission: NotificationPermission {
        switch status {
        case .notDetermined: return .notAsked
        case .denied: return .denied
        case .authorized, .provisional: return .allowed
        }
    }

    /// For the log.
    var logLine: String {
        "authorization \(status.rawValue), banners \(banners ? "on" : "off"), sound \(sound ? "on" : "off"), notification center \(inNotificationCenter ? "on" : "off")"
    }
}

/// The part of `UNUserNotificationCenter` the notifier uses, so a test
/// can stand in for it. The calls answer on any thread.
protocol NotificationCentering: AnyObject {
    func setDelegate(_ delegate: UNUserNotificationCenterDelegate)
    func requestAuthorization(_ done: @escaping (Bool, Error?) -> Void)
    func allowance(_ done: @escaping (NotificationAllowance) -> Void)
    func add(_ request: UNNotificationRequest, _ done: @escaping (Error?) -> Void)
    func removeDelivered(_ identifiers: [String])
}

final class SystemNotificationCenter: NotificationCentering {
    private var center: UNUserNotificationCenter { .current() }

    func setDelegate(_ delegate: UNUserNotificationCenterDelegate) {
        center.delegate = delegate
    }

    func requestAuthorization(_ done: @escaping (Bool, Error?) -> Void) {
        center.requestAuthorization(options: [.alert, .sound], completionHandler: done)
    }

    func allowance(_ done: @escaping (NotificationAllowance) -> Void) {
        center.getNotificationSettings { settings in
            let status: NotificationAllowance.Status
            switch settings.authorizationStatus {
            case .notDetermined: status = .notDetermined
            case .denied: status = .denied
            case .provisional: status = .provisional
            default: status = .authorized
            }
            done(NotificationAllowance(
                status: status, banners: settings.alertSetting == .enabled && settings.alertStyle != .none,
                sound: settings.soundSetting == .enabled, inNotificationCenter: settings.notificationCenterSetting == .enabled
            ))
        }
    }

    func add(_ request: UNNotificationRequest, _ done: @escaping (Error?) -> Void) {
        center.add(request, withCompletionHandler: done)
    }

    func removeDelivered(_ identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

/// The notifications of the app: a safety stop, what the hidden icon
/// cannot show, and an agent that waits or finished.
final class Notifier: NSObject, AgentNotifying, UNUserNotificationCenterDelegate {
    @MainActor static let shared = Notifier(center: SystemNotificationCenter())
    /// States, times and pids only. `notice` and above stay in the log.
    static let log = Logger(subsystem: "com.caffeinagent.app", category: "Notices")

    @MainActor var onPermission: ((NotificationPermission) -> Void)?
    @MainActor var onDelivery: ((String, AgentNoticeDelivery) -> Void)?
    @MainActor var onOpen: ((AgentNoticeTarget) -> Void)?
    private let center: NotificationCentering
    /// The last request of each `AgentNoticeContent.key`.
    @MainActor private var lastIdentifiers: [String: String] = [:]
    @MainActor private var loggedAllowance: NotificationAllowance?

    @MainActor
    init(center: NotificationCentering) {
        self.center = center
        super.init()
        center.setDelegate(self)
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

    static func request(for notice: AgentNoticeContent) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.subtitle = notice.subtitle ?? ""
        content.body = notice.body ?? ""
        content.threadIdentifier = notice.thread
        content.sound = notice.sound ? .default : nil
        // One about several agents has no agent to go to.
        if let agent = notice.agent { content.userInfo = AgentNoticeTarget(agent: agent, ownerPid: notice.ownerPid).userInfo }
        return UNNotificationRequest(identifier: notice.id, content: content, trigger: nil)
    }

    @MainActor
    func post(_ notice: AgentNoticeContent) {
        // The older one about the same session would stay in Notification
        // Center next to the new one.
        if let old = lastIdentifiers[notice.key], old != notice.id { center.removeDelivered([old]) }
        lastIdentifiers[notice.key] = notice.id
        let id = notice.id
        let request = Self.request(for: notice)
        center.requestAuthorization { [weak self, center] granted, error in
            if let error { Self.log.error("authorization failed: \(Self.code(of: error), privacy: .public)") }
            center.allowance { allowance in
                self?.onMain { $0.note(allowance) }
                guard granted else {
                    Self.log.notice("post skipped \(id, privacy: .public): notifications are not allowed")
                    self?.onMain { $0.onDelivery?(id, .notAllowed) }
                    return
                }
                center.add(request) { error in
                    if let error {
                        Self.log.error("post failed \(id, privacy: .public): \(Self.code(of: error), privacy: .public)")
                        self?.onMain { $0.onDelivery?(id, .failed) }
                    } else {
                        Self.log.notice("posted \(id, privacy: .public)\(allowance.banners ? "" : ", banners are off", privacy: .public)")
                        self?.onMain { $0.onDelivery?(id, allowance.banners ? .delivered : .noBanner) }
                    }
                }
            }
        }
    }

    @MainActor
    func requestPermission() {
        center.requestAuthorization { [weak self, center] _, error in
            if let error { Self.log.error("authorization failed: \(Self.code(of: error), privacy: .public)") }
            center.allowance { allowance in self?.onMain { $0.note(allowance) } }
        }
    }

    @MainActor
    func readPermission() {
        center.allowance { [weak self] allowance in self?.onMain { $0.note(allowance) } }
    }

    @MainActor
    func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The domain and the number say enough, and the text of an error
    /// can hold what the notification says.
    private static func code(of error: Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }

    private func onMain(_ work: @escaping @MainActor (Notifier) -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { work(self) } }
    }

    /// Logged at launch and when it changes.
    @MainActor
    private func note(_ allowance: NotificationAllowance) {
        if allowance != loggedAllowance {
            loggedAllowance = allowance
            Self.log.notice("\(allowance.logLine, privacy: .public)")
        }
        onPermission?(allowance.permission)
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Without this macOS shows nothing while agent caffeine is the app
    /// in front, as with Preferences open. The sound is the request's own.
    static func presentation(of content: UNNotificationContent) -> UNNotificationPresentationOptions {
        content.sound == nil ? [.banner, .list] : [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Self.presentation(of: notification.request.content))
    }

    /// A click on a notification about one agent goes to the app that
    /// agent runs in now. Any other click does what macOS does by itself.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let target = AgentNoticeTarget(userInfo: response.notification.request.content.userInfo) {
            onMain { $0.onOpen?(target) }
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
