import XCTest

final class HiddenNoticeTests: XCTestCase {
    func testCurrent() {
        let cases: [(flagLeftOn: Bool, silent: Bool, want: HiddenNotice?)] = [
            (false, false, nil),
            (true, false, .helperSwitchedOff),
            (false, true, .helperNotResponding),
            // The helper that was switched off comes first, as in the menu.
            (true, true, .helperSwitchedOff),
        ]
        for c in cases {
            XCTAssertEqual(HiddenNotice.current(flagLeftOn: c.flagLeftOn, helperNotResponding: c.silent), c.want, "\(c)")
        }
    }

    func testNoticeIsAnnouncedOncePerEvent() {
        let silent = HiddenNotice.helperNotResponding
        XCTAssertEqual(HiddenNotice.toAnnounce(previous: nil, current: silent, iconHidden: true), silent)
        // It goes on.
        XCTAssertNil(HiddenNotice.toAnnounce(previous: silent, current: silent, iconHidden: true))
        XCTAssertNil(HiddenNotice.toAnnounce(previous: silent, current: nil, iconHidden: true))
        // It ended, so the next one is a new event.
        XCTAssertEqual(HiddenNotice.toAnnounce(previous: nil, current: silent, iconHidden: true), silent)
        // Another notice takes its place.
        XCTAssertEqual(HiddenNotice.toAnnounce(previous: silent, current: .helperSwitchedOff, iconHidden: true), .helperSwitchedOff)
        XCTAssertNil(HiddenNotice.toAnnounce(previous: nil, current: nil, iconHidden: true))
    }

    func testNothingIsAnnouncedWhileTheIconIsShown() {
        let silent = HiddenNotice.helperNotResponding
        XCTAssertNil(HiddenNotice.toAnnounce(previous: nil, current: silent, iconHidden: false))
        XCTAssertNil(HiddenNotice.toAnnounce(previous: nil, current: .helperSwitchedOff, iconHidden: false))
        // It began while the menu showed it, so hiding the icon tells nothing.
        XCTAssertNil(HiddenNotice.toAnnounce(previous: silent, current: silent, iconHidden: true))
    }

    func testNotificationText() {
        XCTAssertEqual(HiddenNotice.helperSwitchedOff.notificationText, "Your Mac cannot sleep. Allow Agent Caffeine again in System Settings > General > Login Items.")
        XCTAssertEqual(
            HiddenNotice.helperNotResponding.notificationText,
            "Agent Caffeine cannot reach its helper. Your Mac will sleep when you close the lid on battery."
        )
    }
}
