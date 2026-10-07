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
            workedFor: kind == .finished ? 90 : nil
        )
        return AgentNoticeText.content(AgentNotice(kind: kind, sessions: [session]), outlook: .silent, now: start.addingTimeInterval(seconds))
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

    func testAClickFindsTheAgentOfTheNotification() throws {
        let info = Notifier.request(for: content(.waiting, pid: 7, after: 0)).content.userInfo
        XCTAssertEqual(AgentNoticeTarget(userInfo: info), AgentNoticeTarget(agent: ProcessIdentity(pid: 7, startTime: 5), ownerPid: 500))
        XCTAssertEqual(AgentNoticeTarget(userInfo: Notifier.request(for: content(.finished, pid: 8, after: 0)).content.userInfo)?.agent.pid, 8)
        // As macOS hands it back: through a property list.
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0)
        let stored = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [AnyHashable: Any])
        XCTAssertEqual(AgentNoticeTarget(userInfo: stored), AgentNoticeTarget(agent: ProcessIdentity(pid: 7, startTime: 5), ownerPid: 500))

        let precise = AgentNoticeTarget(agent: ProcessIdentity(pid: 99_999, startTime: 1_791_000_000.123456))
        XCTAssertEqual(AgentNoticeTarget(userInfo: precise.userInfo), precise, "The start time tells a pid that was used again apart")
        XCTAssertNil(precise.userInfo["ownerPid"])
    }

    func testAClickOnANotificationAboutSeveralAgentsGoesToNoAgent() {
        let sessions = (1...3).map {
            AgentNotice.Session(identity: ProcessIdentity(pid: $0, startTime: 5), agentID: "claude", displayName: "Claude Code", ownerPid: 500)
        }
        let summary = AgentNoticeText.content(AgentNotice(kind: .finished, sessions: sessions), outlook: .silent, now: start)
        XCTAssertEqual(summary.title, "3 agents finished")
        XCTAssertNil(summary.agent)
        let info = Notifier.request(for: summary).content.userInfo
        XCTAssertTrue(info.isEmpty)
        XCTAssertNil(AgentNoticeTarget(userInfo: info))
        XCTAssertNil(AgentNoticeTarget(userInfo: ["agentPid": "7", "agentStart": 5.0]), "Not what the notifier wrote")

        // A click after days: the pid of the app can belong to another
        // process. The app of an agent started no later than the agent.
        let target = AgentNoticeTarget(agent: ProcessIdentity(pid: 7, startTime: 1000), ownerPid: 500)
        XCTAssertTrue(target.ownerIsStill(startTime: 400), "The terminal the agent was started in")
        XCTAssertTrue(target.ownerIsStill(startTime: 1000), "The agent is the app")
        XCTAssertTrue(target.ownerIsStill(startTime: 1000.0005), "Two readings of one start time")
        XCTAssertFalse(target.ownerIsStill(startTime: 5000), "Another process got the pid")
        XCTAssertFalse(target.ownerIsStill(startTime: nil), "No process has the pid")
        XCTAssertFalse(AgentNoticeTarget(agent: target.agent).ownerIsStill(startTime: 400), "No app was known")
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
        XCTAssertEqual(Notifier.presentation(of: finished), [.banner, .list, .sound])
        let silent = UNMutableNotificationContent()
        XCTAssertEqual(Notifier.presentation(of: silent), [.banner, .list], "A request without a sound stays silent")
    }
}
