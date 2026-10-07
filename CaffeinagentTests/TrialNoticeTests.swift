import XCTest

final class TrialNoticeTests: XCTestCase {
    func testEachNoticeIsDueOnce() {
        let cases: [(Entitlement, Set<TrialNotice>, TrialNotice?)] = [
            (.trial(daysLeft: 7), [], nil),
            (.trial(daysLeft: 2), [], nil),
            (.trial(daysLeft: 1), [], .endsSoon),
            (.trial(daysLeft: 1), [.endsSoon], nil),
            (.expired(.trialOver), [], .ended),
            (.expired(.trialOver), [.endsSoon], .ended),
            (.expired(.trialOver), [.endsSoon, .ended], nil),
            // The app did not run on the last day: the end is still told.
            (.expired(.trialOver), [.ended], nil),
            // A paying user is never told about a trial.
            (.licensed, [], nil),
            (.expired(.unverified), [], nil),
            (.expired(.activationRemoved), [], nil),
        ]
        for (entitlement, told, want) in cases {
            XCTAssertEqual(TrialNotice.due(entitlement: entitlement, told: told), want, "\(entitlement) \(told)")
        }
    }

    func testWhatWasToldLastsOverARestart() throws {
        let name = "TrialNoticeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(TrialNoticeStore.load(from: defaults), [])
        TrialNoticeStore.save([.endsSoon], to: defaults)
        XCTAssertEqual(TrialNoticeStore.load(from: defaults), [.endsSoon])
        TrialNoticeStore.save([.endsSoon, .ended], to: defaults)
        XCTAssertEqual(TrialNoticeStore.load(from: defaults), [.endsSoon, .ended])
        defaults.set(["ended", "something else"], forKey: TrialNoticeStore.key)
        XCTAssertEqual(TrialNoticeStore.load(from: defaults), [.ended])
    }

    func testTexts() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_000_000) // 13:46
        let today = now.addingTimeInterval(3 * 3600)
        let tomorrow = now.addingTimeInterval(20 * 3600)
        XCTAssertEqual(
            PanelText.notification(.endsSoon, end: tomorrow, now: now, calendar: calendar),
            "Your agent caffeine trial ends tomorrow. After that it does not keep your Mac awake without a license key."
        )
        XCTAssertEqual(
            PanelText.notification(.endsSoon, end: today, now: now, calendar: calendar),
            "Your agent caffeine trial ends today. After that it does not keep your Mac awake without a license key."
        )
        XCTAssertEqual(
            PanelText.notification(.ended, end: today, now: now, calendar: calendar),
            "Your agent caffeine trial has ended. agent caffeine does not keep your Mac awake until you enter a license key."
        )
    }

    /// Every day of the trial reads well in Settings > License.
    func testTheStatusOfEachDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_000_000)
        let texts = (1...7).reversed().map { PanelText.trialStatus(daysLeft: $0, end: now.addingTimeInterval(20 * 3600), now: now, calendar: calendar) }
        XCTAssertEqual(texts, [
            "Your free trial has 7 days left.", "Your free trial has 6 days left.", "Your free trial has 5 days left.",
            "Your free trial has 4 days left.", "Your free trial has 3 days left.", "Your free trial has 2 days left.",
            "Your free trial ends tomorrow.",
        ])
        XCTAssertEqual(PanelText.trialStatus(daysLeft: 1, end: now.addingTimeInterval(3600), now: now, calendar: calendar), "Your free trial ends today.")
        XCTAssertEqual(PanelText.trialStatus(daysLeft: 1, end: nil, now: now, calendar: calendar), "Your free trial ends today.")
    }

    /// The setup window names the length of the trial from the rule.
    func testTheIntroNamesTheLengthOfTheTrial() {
        XCTAssertEqual(PanelText.trialDays, 7)
        XCTAssertEqual(
            PanelText.trialIntro,
            "Your free trial runs for 7 days. After that, agent caffeine needs a license key to keep your Mac awake."
        )
        XCTAssertEqual(Onboarding.trialNote(.trial(daysLeft: 7)), PanelText.trialIntro)
        XCTAssertNil(Onboarding.trialNote(.licensed))
        XCTAssertNil(Onboarding.trialNote(.expired(.trialOver)))
    }
}
