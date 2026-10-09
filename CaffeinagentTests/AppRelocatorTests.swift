import XCTest

final class AppRelocatorTests: XCTestCase {
    func testWhereTheAppRunsFrom() {
        let home = "/Users/me"
        let cases: [(path: String, readOnly: Bool, want: AppRelocator.Location)] = [
            ("/Applications/Agent Caffeine.app", false, .installed),
            ("/Applications/agent caffeine.app", false, .installed),
            ("/Users/me/Applications/agent caffeine.app", false, .installed),
            // The mounted disk image.
            ("/Volumes/Agent Caffeine/Agent Caffeine.app", true, .cannotMove),
            ("/Volumes/Agent Caffeine/agent caffeine.app", true, .cannotMove),
            // A copy that is kept on an external drive: the alert of the
            // disk image came at every launch.
            ("/Volumes/Work/Apps/agent caffeine.app", false, .elsewhere),
            // A quarantined download that was opened where it is.
            ("/private/var/folders/ab/T/AppTranslocation/1234-ABCD/d/agent caffeine.app", true, .cannotMove),
            ("/private/var/folders/ab/T/AppTranslocation/1234-ABCD/d/agent caffeine.app", false, .cannotMove),
            ("/Users/me/Downloads/agent caffeine.app", false, .elsewhere),
            ("/Users/other/Applications/agent caffeine.app", false, .elsewhere),
            ("/Applications", false, .elsewhere),
        ]
        for c in cases {
            XCTAssertEqual(AppRelocator.location(of: c.path, home: home, volumeIsReadOnly: c.readOnly), c.want, c.path)
        }
    }

    func testAVolumeThatCanBeWrittenIsNoDiskImage() {
        XCTAssertFalse(AppRelocator.volumeIsReadOnly(of: FileManager.default.temporaryDirectory))
        XCTAssertTrue(AppRelocator.volumeIsReadOnly(of: URL(fileURLWithPath: "/no/such/folder/agent caffeine.app")), "Not known: as on a disk image")
    }

    func testTheWordsOfTheAlertOnADiskImage() {
        XCTAssertEqual(AppRelocator.dragTitle, "Move Agent Caffeine to the Applications folder")
        XCTAssertEqual(AppRelocator.dragText, "Drag Agent Caffeine to the Applications folder, then open it from there.")
        XCTAssertEqual(AppRelocator.dragQuit, "Quit")
        XCTAssertEqual(AppRelocator.dragContinue, "Continue anyway")
    }
}
