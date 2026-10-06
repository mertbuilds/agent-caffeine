import XCTest

final class HiddenNoticeTests: XCTestCase {
    func testCurrent() {
        let cases: [(flagLeftOn: Bool, entitlement: Entitlement, want: HiddenNotice?)] = [
            (false, .licensed, nil),
            (false, .trial(daysLeft: 1), nil),
            (false, .expired(.trialOver), .licenseExpired(.trialOver)),
            (false, .expired(.unverified), .licenseExpired(.unverified)),
            (false, .expired(.activationRemoved), .licenseExpired(.activationRemoved)),
            (true, .licensed, .helperSwitchedOff),
            // The helper comes first, as in the menu.
            (true, .expired(.trialOver), .helperSwitchedOff),
        ]
        for c in cases {
            XCTAssertEqual(HiddenNotice.current(flagLeftOn: c.flagLeftOn, entitlement: c.entitlement), c.want, "\(c)")
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
    }

    func testNothingIsAnnouncedWhileTheIconIsShown() {
        let over = HiddenNotice.licenseExpired(.trialOver)
        XCTAssertNil(HiddenNotice.toAnnounce(previous: nil, current: over, iconHidden: false))
        XCTAssertNil(HiddenNotice.toAnnounce(previous: nil, current: .helperSwitchedOff, iconHidden: false))
        // It began while the menu showed it, so hiding the icon tells nothing.
        XCTAssertNil(HiddenNotice.toAnnounce(previous: over, current: over, iconHidden: true))
    }

    func testNotificationText() {
        XCTAssertEqual(HiddenNotice.helperSwitchedOff.notificationText, "agent caffeine cannot let your Mac sleep because it was switched off in Login Items")
        XCTAssertEqual(HiddenNotice.licenseExpired(.trialOver).notificationText, "agent caffeine cannot keep your Mac awake because your trial has ended")
        XCTAssertEqual(HiddenNotice.licenseExpired(.unverified).notificationText, "agent caffeine cannot keep your Mac awake because your license was not checked for 30 days")
        XCTAssertEqual(HiddenNotice.licenseExpired(.activationRemoved).notificationText, "agent caffeine cannot keep your Mac awake because this Mac is no longer activated")
    }
}
