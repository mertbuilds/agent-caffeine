import XCTest

final class HiddenNoticeTests: XCTestCase {
    func testCurrent() {
        let cases: [(flagLeftOn: Bool, silent: Bool, entitlement: Entitlement, want: HiddenNotice?)] = [
            (false, false, .licensed, nil),
            (false, false, .trial(daysLeft: 1), nil),
            // The end of the trial has a notification of its own.
            (false, false, .expired(.trialOver), nil),
            (false, false, .expired(.unverified), .licenseExpired(.unverified)),
            (false, false, .expired(.activationRemoved), .licenseExpired(.activationRemoved)),
            (true, false, .licensed, .helperSwitchedOff),
            (false, true, .licensed, .helperNotResponding),
            // The helper comes first, as in the menu.
            (true, false, .expired(.trialOver), .helperSwitchedOff),
            (false, true, .expired(.trialOver), .helperNotResponding),
            (true, true, .licensed, .helperSwitchedOff),
        ]
        for c in cases {
            XCTAssertEqual(
                HiddenNotice.current(flagLeftOn: c.flagLeftOn, helperNotResponding: c.silent, entitlement: c.entitlement), c.want, "\(c)"
            )
        }
    }

    func testNoticeIsAnnouncedOncePerEvent() {
        let over = HiddenNotice.licenseExpired(.trialOver)
        XCTAssertEqual(HiddenNotice.toAnnounce(previous: nil, current: over, iconHidden: true), over)
        // It goes on.
        XCTAssertNil(HiddenNotice.toAnnounce(previous: over, current: over, iconHidden: true))
        XCTAssertNil(HiddenNotice.toAnnounce(previous: over, current: nil, iconHidden: true))
        // It ended, so the next one is a new event.
        XCTAssertEqual(HiddenNotice.toAnnounce(previous: nil, current: over, iconHidden: true), over)
        // Another notice takes its place.
        XCTAssertEqual(HiddenNotice.toAnnounce(previous: over, current: .helperSwitchedOff, iconHidden: true), .helperSwitchedOff)
        XCTAssertNil(HiddenNotice.toAnnounce(previous: nil, current: nil, iconHidden: true))
        // The helper stops answering, answers again, and stops once more.
        XCTAssertEqual(HiddenNotice.toAnnounce(previous: nil, current: .helperNotResponding, iconHidden: true), .helperNotResponding)
        XCTAssertNil(HiddenNotice.toAnnounce(previous: .helperNotResponding, current: .helperNotResponding, iconHidden: true))
        XCTAssertNil(HiddenNotice.toAnnounce(previous: .helperNotResponding, current: nil, iconHidden: true))
        XCTAssertEqual(HiddenNotice.toAnnounce(previous: nil, current: .helperNotResponding, iconHidden: true), .helperNotResponding)
    }

    func testNothingIsAnnouncedWhileTheIconIsShown() {
        let over = HiddenNotice.licenseExpired(.trialOver)
        XCTAssertNil(HiddenNotice.toAnnounce(previous: nil, current: over, iconHidden: false))
        XCTAssertNil(HiddenNotice.toAnnounce(previous: nil, current: .helperSwitchedOff, iconHidden: false))
        XCTAssertNil(HiddenNotice.toAnnounce(previous: nil, current: .helperNotResponding, iconHidden: false))
        // It began while the menu showed it, so hiding the icon tells nothing.
        XCTAssertNil(HiddenNotice.toAnnounce(previous: over, current: over, iconHidden: true))
    }

    func testNotificationText() {
        XCTAssertEqual(HiddenNotice.helperSwitchedOff.notificationText, "Your Mac cannot sleep. Allow agent caffeine again in System Settings > General > Login Items.")
        XCTAssertEqual(
            HiddenNotice.helperNotResponding.notificationText,
            "agent caffeine cannot reach its helper. Your Mac will sleep when you close the lid on battery."
        )
        XCTAssertEqual(HiddenNotice.licenseExpired(.trialOver).notificationText, "agent caffeine cannot keep your Mac awake because your trial has ended")
        XCTAssertEqual(HiddenNotice.licenseExpired(.unverified).notificationText, "agent caffeine cannot keep your Mac awake because your license was not checked for 30 days")
        XCTAssertEqual(HiddenNotice.licenseExpired(.activationRemoved).notificationText, "agent caffeine cannot keep your Mac awake because this Mac is no longer activated")
    }
}
