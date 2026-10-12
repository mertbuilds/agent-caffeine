import XCTest

final class PaidLeftoversTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = TestDefaults()
    }

    private var remembered: Bool { defaults.bool(forKey: PaidLeftovers.removedKey) }

    /// As the paid versions wrote them.
    private static let left = ["License.trialStart", "License.latestSeen", "License.lastValidated", "TrialNotice.told"]

    /// - Returns: how often the Keychain was asked.
    private func remove(itemGone: Bool) -> Int {
        var asked = 0
        PaidLeftovers.remove(defaults: defaults) {
            asked += 1
            return itemGone
        }
        return asked
    }

    func testTheSettingsAndTheKeychainItemGoOnce() {
        Self.left.forEach { defaults.set("left", forKey: $0) }
        XCTAssertEqual(remove(itemGone: true), 1)
        for key in Self.left {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
        XCTAssertTrue(remembered)
        XCTAssertEqual(remove(itemGone: true), 0, "Once")
    }

    func testAnItemThatStayedIsTriedAgainAtTheNextLaunch() {
        XCTAssertEqual(remove(itemGone: false), 1)
        XCTAssertFalse(remembered)
        XCTAssertEqual(remove(itemGone: false), 1)
        XCTAssertEqual(remove(itemGone: true), 1)
        XCTAssertTrue(remembered)
    }

    func testOtherSettingsStay() {
        defaults.set(false, forKey: "enabled")
        _ = remove(itemGone: true)
        XCTAssertEqual(defaults.object(forKey: "enabled") as? Bool, false)
    }

    /// Debug and Release share the settings and not the Keychain item.
    /// A Debug build that found no item of its own must not make the
    /// Release build skip the real one.
    func testADebugBuildRemembersUnderAKeyOfItsOwn() {
        XCTAssertEqual(PaidLeftovers.removedKey.hasSuffix(".debug"), PaidLeftovers.keychainService.hasSuffix(".debug"))
        #if DEBUG
        XCTAssertEqual(PaidLeftovers.removedKey, "PaidLeftovers.removed.debug")
        XCTAssertEqual(remove(itemGone: true), 1)
        XCTAssertFalse(defaults.bool(forKey: "PaidLeftovers.removed"), "The Release build still cleans up")
        #else
        XCTAssertEqual(PaidLeftovers.removedKey, "PaidLeftovers.removed")
        #endif
    }

    func testTheKeychainItemIsThatOfThePaidVersions() {
        XCTAssertTrue(PaidLeftovers.keychainService.hasPrefix("com.caffeinagent.app.license"))
        XCTAssertEqual(PaidLeftovers.keychainAccount, "license")
    }
}
