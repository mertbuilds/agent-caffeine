import XCTest

/// What counts as online: `NetworkPath.isOnline`, with paths that are
/// passed in. No test reads the network of the Mac.
final class NetworkPathTests: XCTestCase {
    private func path(_ satisfied: Bool, _ interfaces: [(NetworkPath.Kind, String)]) -> NetworkPath {
        NetworkPath(satisfied: satisfied, interfaces: interfaces.map { NetworkPath.Interface(kind: $0.0, name: $0.1) })
    }

    func testWiFiEthernetAndAPhoneLinkAreOnline() {
        XCTAssertTrue(path(true, [(.wifi, "en0")]).isOnline)
        XCTAssertTrue(path(true, [(.wired, "en7")]).isOnline)
        XCTAssertTrue(path(true, [(.cellular, "pdp_ip0")]).isOnline)
    }

    func testAPathThatIsNotSatisfiedIsOffline() {
        XCTAssertFalse(path(false, [(.wifi, "en0")]).isOnline)
        XCTAssertFalse(path(false, []).isOnline)
    }

    func testNoInterfaceIsOffline() {
        XCTAssertFalse(path(true, []).isOnline)
    }

    func testLoopbackAloneIsOffline() {
        XCTAssertFalse(path(true, [(.loopback, "lo0")]).isOnline)
    }

    /// A VPN keeps its tunnel as the default path after the Wi-Fi under
    /// it is gone.
    func testATunnelOfAVPNAloneIsOffline() {
        XCTAssertFalse(path(true, [(.other, "utun3")]).isOnline)
        XCTAssertFalse(path(true, [(.other, "ipsec0")]).isOnline)
        XCTAssertFalse(path(true, [(.other, "ppp0")]).isOnline)
        XCTAssertFalse(path(true, [(.other, "utun3"), (.loopback, "lo0")]).isOnline)
    }

    func testAVPNOverWiFiIsOnline() {
        XCTAssertTrue(path(true, [(.other, "utun3"), (.wifi, "en0")]).isOnline)
    }

    /// A link macOS has no type for is a link: it never reads as offline.
    func testAnUnknownLinkThatIsNoTunnelIsOnline() {
        XCTAssertTrue(path(true, [(.other, "bridge0")]).isOnline)
    }
}
