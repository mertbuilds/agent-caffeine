import UserNotifications
import XCTest

/// Stands in for `UNUserNotificationCenter`. It answers at once.
private final class FakeCenter: NotificationCentering {
    var granted = true
    var allowance = NotificationAllowance(status: .authorized)
    var addError: Error?
    var delegates = 0
    var requests: [UNNotificationRequest] = []
    var removed: [String] = []

    func setDelegate(_ delegate: UNUserNotificationCenterDelegate) { delegates += 1 }
    func requestAuthorization(_ done: @escaping (Bool, Error?) -> Void) { done(granted, nil) }
    func allowance(_ done: @escaping (NotificationAllowance) -> Void) { done(allowance) }
    func removeDelivered(_ identifiers: [String]) { removed += identifiers }

    func add(_ request: UNNotificationRequest, _ done: @escaping (Error?) -> Void) {
        if addError == nil { requests.append(request) }
        done(addError)
    }
}

@MainActor
final class NotifierTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private var center = FakeCenter()
    private var deliveries: [String: AgentNoticeDelivery] = [:]
    private var permissions: [NotificationPermission] = []

    private func notifier() -> Notifier {
        let notifier = Notifier(center: center)
        notifier.onDelivery = { [weak self] id, delivery in self?.deliveries[id] = delivery }
        notifier.onPermission = { [weak self] permission in self?.permissions.append(permission) }
        return notifier
    }

    private func content(_ kind: AgentNoticeKind, pid: Int32 = 7, after seconds: TimeInterval) -> AgentNoticeContent {
        let session = AgentNotice.Session(
            identity: ProcessIdentity(pid: pid, startTime: 5), agentID: "claude", displayName: "Claude Code", label: "wiki", ownerPid: 500,
            workedFor: kind == .finished ? 90 : nil, waitingSince: kind == .waiting ? start : nil
        )
        return AgentNoticeText.content(AgentNotice(kind: kind, sessions: [session]), waitingHold: nil, now: start.addingTimeInterval(seconds))
    }

    /// The answers of the centre come back on the main queue.
    private func settle() async {
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
    }

    func testTheNotifierIsTheDelegateOfTheCentre() {
        _ = notifier()
        XCTAssertEqual(center.delegates, 1, "Without a delegate macOS shows nothing while the app is in front")
    }

    func testEachPostIsARequestOfItsOwnInTheThreadOfTheAgent() async {
        let notifier = notifier()
        notifier.post(content(.finished, after: 0))
        notifier.post(content(.finished, after: 60))
        notifier.post(content(.waiting, after: 90))
        notifier.post(content(.finished, pid: 8, after: 90))
        await settle()
        XCTAssertEqual(center.requests.count, 4)
        XCTAssertEqual(Set(center.requests.map(\.identifier)).count, 4, "A request with a known identifier shows no new banner")
        XCTAssertEqual(Set(center.requests.map(\.content.threadIdentifier)), ["agent-claude"])
        XCTAssertEqual(center.removed, [center.requests[0].identifier], "The older one about the same session and kind leaves Notification Center")
        XCTAssertEqual(center.requests.map { deliveries[$0.identifier] }, [.delivered, .delivered, .delivered, .delivered])
        XCTAssertEqual(center.requests[0].content.title, "Claude Code finished")
        XCTAssertEqual(center.requests[0].content.subtitle, "wiki")
        XCTAssertNil(center.requests[0].trigger)
    }

    func testWhatBecomesOfAPostIsReported() async {
        let notifier = notifier()
        center.allowance = NotificationAllowance(status: .authorized, banners: false)
        let quiet = content(.finished, after: 0)
        notifier.post(quiet)
        await settle()
        XCTAssertEqual(deliveries[quiet.id], .noBanner)

        center.addError = NSError(domain: UNErrorDomain, code: 1)
        let failed = content(.finished, after: 10)
        notifier.post(failed)
        await settle()
        XCTAssertEqual(deliveries[failed.id], .failed)

        center.addError = nil
        center.granted = false
        center.allowance = NotificationAllowance(status: .denied)
        let refused = content(.waiting, after: 20)
        notifier.post(refused)
        await settle()
        XCTAssertEqual(deliveries[refused.id], .notAllowed)
        XCTAssertEqual(center.requests.count, 1)
        XCTAssertEqual(permissions.last, .denied)
    }

    func testThePermissionIsReadWithoutAQuestion() async {
        let notifier = notifier()
        center.allowance = NotificationAllowance(status: .notDetermined)
        notifier.readPermission()
        await settle()
        center.allowance = NotificationAllowance(status: .provisional)
        notifier.readPermission()
        await settle()
        XCTAssertEqual(permissions, [.notAsked, .allowed])
        XCTAssertEqual(center.requests, [])
    }

    func testTheAllowanceInTheLog() {
        XCTAssertEqual(
            NotificationAllowance(status: .authorized, banners: false, sound: true, inNotificationCenter: true).logLine,
            "authorization authorized, banners off, sound on, notification center on"
        )
    }

    func testANotificationIsShownWhileTheAppIsInFront() {
        let waiting = Notifier.request(for: content(.waiting, after: 0)).content
        let finished = Notifier.request(for: content(.finished, after: 0)).content
        XCTAssertEqual(Notifier.presentation(of: waiting), [.banner, .list, .sound])
        XCTAssertEqual(Notifier.presentation(of: finished), [.banner, .list], "Finished is silent")
    }
}
