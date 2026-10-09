import XCTest

/// A volume that stands in for the one `/Applications` is on. The paths
/// are the items on it, with their names as written on disk.
struct FakeVolume {
    var caseSensitive: Bool
    var items: [String]

    private func index(of path: String) -> Int? {
        items.firstIndex { caseSensitive ? $0 == path : $0.caseInsensitiveCompare(path) == .orderedSame }
    }

    var install: AppInstall {
        AppInstall(
            identity: { path in index(of: path).map { AppInstall.FileIdentity(device: 1, inode: UInt64($0)) } },
            caseSensitive: { _ in caseSensitive },
            names: { folder in items.filter { ($0 as NSString).deletingLastPathComponent == folder }.map { ($0 as NSString).lastPathComponent } }
        )
    }
}

/// The name of the bundle on disk: `Agent Caffeine.app` for a new install,
/// `agent caffeine.app` for one that was updated from 1.0.0 or 1.0.1, on a
/// volume that tells names apart by case and on one that does not. No
/// test here reads `/Applications`.
final class AppInstallTests: XCTestCase {
    private let new = "/Applications/Agent Caffeine.app"
    private let earlier = "/Applications/agent caffeine.app"

    private func volume(caseSensitive: Bool, _ items: String...) -> AppInstall {
        FakeVolume(caseSensitive: caseSensitive, items: items).install
    }

    func testTheTwoNamesAreOneBundleOnlyWhereTheVolumeKeepsNoCaseApart() {
        for onDisk in [new, earlier] {
            let plain = volume(caseSensitive: false, onDisk)
            XCTAssertTrue(plain.isSameItem(new, earlier), onDisk)
            XCTAssertTrue(plain.isSameItem(earlier, new), onDisk)
            let strict = volume(caseSensitive: true, onDisk)
            XCTAssertFalse(strict.isSameItem(new, earlier), onDisk)
            XCTAssertFalse(strict.isSameItem(earlier, new), onDisk)
            XCTAssertTrue(strict.isSameItem(onDisk, onDisk))
        }
        // Two installs next to each other are two bundles.
        XCTAssertFalse(volume(caseSensitive: true, new, earlier).isSameItem(new, earlier))
        // Another copy is another bundle on every volume.
        let copies = volume(caseSensitive: false, earlier, "/Users/me/Downloads/Agent Caffeine.app")
        XCTAssertFalse(copies.isSameItem(earlier, "/Users/me/Downloads/Agent Caffeine.app"))
        XCTAssertFalse(copies.isSameItem(earlier, "/Users/me/Downloads/gone.app"), "One of the two is not there")
    }

    /// With nothing on disk the names decide, as the volume would read them.
    func testWithoutAFileTheNamesDecideAsTheVolumeReadsThem() {
        XCTAssertTrue(volume(caseSensitive: false).isSameItem(new, earlier))
        XCTAssertFalse(volume(caseSensitive: true).isSameItem(new, earlier))
        XCTAssertFalse(volume(caseSensitive: false).isSameItem(new, "/Applications/Other.app"))
        let silent = AppInstall(identity: { _ in nil }, caseSensitive: { _ in nil }, names: { _ in [] })
        XCTAssertFalse(silent.isSameItem(new, earlier), "A volume that does not say: to the letter")
        XCTAssertTrue(silent.isSameItem(new, new))
    }

    func testTheCopyInTheApplicationsFolderIsTheInstallUnderBothNames() {
        let cases: [(sensitive: Bool, onDisk: String, running: String, want: Bool)] = [
            (false, new, new, true),
            (false, earlier, earlier, true),
            // The same bundle, asked for with the other name.
            (false, earlier, new, true),
            (false, new, earlier, true),
            (false, earlier, "/APPLICATIONS/AGENT CAFFEINE.APP", true),
            (true, new, new, true),
            (true, earlier, earlier, true),
            (false, earlier, "/Users/me/Downloads/Agent Caffeine.app", false),
            (true, earlier, "/Users/me/Downloads/agent caffeine.app", false),
            (false, earlier, "/Users/me/build/Debug/caffeinagent.app", false),
        ]
        for c in cases {
            let install = volume(caseSensitive: c.sensitive, c.onDisk, c.sensitive ? c.running : "/Users/me/Downloads/Agent Caffeine.app", "/Users/me/build/Debug/caffeinagent.app")
            XCTAssertEqual(install.isStableInstall(c.running), c.want, "\(c)")
        }
    }

    /// The path that is written is the name on disk, never one that is not there.
    func testThePathThatIsWrittenHasTheNameOnDisk() {
        let debug = "/Users/me/build/Debug/caffeinagent.app"
        for sensitive in [false, true] {
            // A new install, and one that was updated from 1.0.1.
            XCTAssertEqual(volume(caseSensitive: sensitive, new).stablePath(running: new), new)
            XCTAssertEqual(volume(caseSensitive: sensitive, earlier).stablePath(running: earlier), earlier)
            // A copy from another folder writes the path of the install that is there.
            XCTAssertEqual(volume(caseSensitive: sensitive, earlier, debug).stablePath(running: debug), earlier)
            XCTAssertEqual(volume(caseSensitive: sensitive, new, debug).stablePath(running: debug), new)
            // No install: where a new one goes.
            XCTAssertEqual(volume(caseSensitive: sensitive, debug).stablePath(running: debug), new)
        }
        // Started with the other name: the name on disk is written.
        XCTAssertEqual(volume(caseSensitive: false, earlier).stablePath(running: new), earlier)
        XCTAssertEqual(volume(caseSensitive: false, new).stablePath(running: earlier), new)
        // Two installs: each one writes its own path.
        let both = volume(caseSensitive: true, new, earlier, debug)
        XCTAssertEqual(both.stablePath(running: new), new)
        XCTAssertEqual(both.stablePath(running: earlier), earlier)
        XCTAssertEqual(both.stablePath(running: debug), new)
    }

    func testTheOtherNameIsTheSameBundleOrGoneOrAnotherInstall() {
        XCTAssertEqual(volume(caseSensitive: false, new).spellings(of: new), AppPathSpellings(same: [earlier], gone: []))
        XCTAssertEqual(volume(caseSensitive: false, earlier).spellings(of: earlier), AppPathSpellings(same: [new], gone: []))
        XCTAssertEqual(volume(caseSensitive: true, new).spellings(of: new), AppPathSpellings(same: [], gone: [earlier]))
        XCTAssertEqual(volume(caseSensitive: true, earlier).spellings(of: earlier), AppPathSpellings(same: [], gone: [new]))
        XCTAssertEqual(volume(caseSensitive: true, new, earlier).spellings(of: new), AppPathSpellings(), "Another install: its entries are not ours to move")
        // No install at all, as for a build that runs from its build folder.
        XCTAssertEqual(volume(caseSensitive: false).spellings(of: new), AppPathSpellings(same: [earlier], gone: []))
        XCTAssertEqual(volume(caseSensitive: true).spellings(of: new), AppPathSpellings(same: [], gone: [earlier]))
    }

    func testWhatTheCopyThatRunsFinds() {
        let updated = AppInstall.Running(bundlePath: earlier, install: volume(caseSensitive: false, earlier))
        XCTAssertEqual(updated.path, earlier)
        XCTAssertEqual(updated.stablePath, earlier)
        XCTAssertTrue(updated.isStableInstall)
        XCTAssertEqual(updated.spellings, AppPathSpellings(same: [new], gone: []))

        let fresh = AppInstall.Running(bundlePath: new, install: volume(caseSensitive: true, new))
        XCTAssertEqual(fresh.path, new)
        XCTAssertEqual(fresh.stablePath, new)
        XCTAssertTrue(fresh.isStableInstall)
        XCTAssertEqual(fresh.spellings, AppPathSpellings(same: [], gone: [earlier]))

        let image = "/Volumes/Agent Caffeine/Agent Caffeine.app"
        let fromImage = AppInstall.Running(bundlePath: image, install: volume(caseSensitive: false, earlier, image))
        XCTAssertEqual(fromImage.path, image)
        XCTAssertEqual(fromImage.stablePath, earlier)
        XCTAssertFalse(fromImage.isStableInstall)
    }

    /// A copy from the disk image of 1.0.2 takes the place and the name of
    /// an install of 1.0.1, also where the volume would keep both.
    func testACopyThatMovesInTakesThePlaceOfTheInstallThatIsThere() {
        let name = AppInstall.bundleName
        XCTAssertEqual(volume(caseSensitive: false).relocationPath(for: name), new)
        XCTAssertEqual(volume(caseSensitive: true).relocationPath(for: name), new)
        XCTAssertEqual(volume(caseSensitive: true, new).relocationPath(for: name), new)
        XCTAssertEqual(volume(caseSensitive: true, earlier).relocationPath(for: name), earlier)
        XCTAssertEqual(volume(caseSensitive: true, new).relocationPath(for: AppInstall.earlierBundleName), new)
        XCTAssertEqual(volume(caseSensitive: true, new, earlier).relocationPath(for: name), new)
        // The volume gives the install that is there for either name.
        XCTAssertEqual(volume(caseSensitive: false, earlier).relocationPath(for: name), new)
        // A name the user gave is kept.
        XCTAssertEqual(volume(caseSensitive: true, earlier).relocationPath(for: "My Caffeine.app"), "/Applications/My Caffeine.app")
    }

    /// The real answers, on the volume of the temp folder, whichever kind it is.
    func testTheRealVolumeIsAskedForTheFileAndNotForTheText() throws {
        let live = AppInstall.live
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("app-install-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let onDisk = folder.appendingPathComponent(AppInstall.earlierBundleName)
        try FileManager.default.createDirectory(at: onDisk, withIntermediateDirectories: true)
        let other = folder.appendingPathComponent(AppInstall.bundleName).path
        let sensitive = try XCTUnwrap(live.caseSensitive(onDisk.path))
        XCTAssertEqual(live.caseSensitive(folder.appendingPathComponent("not/there.app").path), sensitive, "The volume of the folder above")
        XCTAssertEqual(live.isSameItem(onDisk.path, other), !sensitive)
        XCTAssertEqual(live.identity(other) != nil, !sensitive)
        XCTAssertEqual(live.names(folder.path), [AppInstall.earlierBundleName], "The name as it was written")
        XCTAssertNil(live.identity(folder.appendingPathComponent("gone.app").path))
        let link = folder.appendingPathComponent("link.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: onDisk)
        XCTAssertTrue(live.isSameItem(link.path, onDisk.path), "A link is followed")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Other.app"), withIntermediateDirectories: true)
        XCTAssertFalse(live.isSameItem(onDisk.path, folder.appendingPathComponent("Other.app").path))
    }
}
