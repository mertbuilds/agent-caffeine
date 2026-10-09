import XCTest

final class MenuBarVisibilityTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = TestDefaults()
    }

    /// A fresh install, and the first launch after an update.
    func testMissingValueCountsAsShown() {
        XCTAssertTrue(MenuBarVisibility.isShown(in: defaults))
        XCTAssertNil(defaults.object(forKey: MenuBarVisibility.key))
    }

    func testSaveAndLoad() {
        MenuBarVisibility.set(false, in: defaults)
        XCTAssertFalse(MenuBarVisibility.isShown(in: defaults))
        MenuBarVisibility.set(true, in: defaults)
        XCTAssertTrue(MenuBarVisibility.isShown(in: defaults))
    }

    func testValueThatIsNoBooleanCountsAsShown() {
        defaults.set("hidden", forKey: MenuBarVisibility.key)
        XCTAssertTrue(MenuBarVisibility.isShown(in: defaults))
    }
}
