import XCTest

final class AppRelocatorTests: XCTestCase {
    func testWhereTheAppRunsFrom() {
        let home = "/Users/me"
        let cases: [(path: String, want: AppRelocator.Location)] = [
            ("/Applications/agent caffeine.app", .installed),
            ("/Users/me/Applications/agent caffeine.app", .installed),
            // The mounted disk image.
            ("/Volumes/agent caffeine/agent caffeine.app", .cannotMove),
            // A quarantined download that was opened where it is.
            ("/private/var/folders/ab/T/AppTranslocation/1234-ABCD/d/agent caffeine.app", .cannotMove),
            ("/Users/me/Downloads/agent caffeine.app", .elsewhere),
            ("/Users/other/Applications/agent caffeine.app", .elsewhere),
            ("/Applications", .elsewhere),
        ]
        for c in cases {
            XCTAssertEqual(AppRelocator.location(of: c.path, home: home), c.want, c.path)
        }
    }

    func testTheWordsOfTheAlertOnADiskImage() {
        XCTAssertEqual(AppRelocator.dragTitle, "Move agent caffeine to the Applications folder")
        XCTAssertEqual(AppRelocator.dragText, "Drag agent caffeine to the Applications folder, then open it from there.")
        XCTAssertEqual(AppRelocator.dragQuit, "Quit")
        XCTAssertEqual(AppRelocator.dragContinue, "Continue anyway")
    }
}
