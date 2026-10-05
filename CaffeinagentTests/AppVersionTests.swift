import XCTest

final class AppVersionTests: XCTestCase {
    func testDisplay() {
        XCTAssertEqual(AppVersion.display(version: "0.2.3", build: "13"), "Version 0.2.3 (13)")
        XCTAssertEqual(AppVersion.display(version: "0.2.3", build: nil), "Version 0.2.3")
        XCTAssertEqual(AppVersion.display(version: "0.2.3", build: ""), "Version 0.2.3")
        XCTAssertEqual(AppVersion.display(version: nil, build: nil), "Version unknown")
    }
}
