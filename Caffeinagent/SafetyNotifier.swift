import UserNotifications

/// Tells the user that agent caffeine stopped keeping the Mac awake to
/// protect it.
enum SafetyNotifier {
    /// macOS asks for permission the first time. Without permission nothing
    /// is shown. A new notice replaces the one before it.
    static func post(_ text: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.body = text
            center.add(UNNotificationRequest(identifier: "safety-stop", content: content, trigger: nil))
        }
    }
}
