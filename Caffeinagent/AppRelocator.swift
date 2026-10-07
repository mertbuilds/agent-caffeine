import AppKit
import Foundation
import os

enum AppRelocator {
    private static let declinedKey = "AppRelocator.userDeclined"
    private static let log = Logger(subsystem: "com.caffeinagent.app", category: "AppRelocator")

    /// The root helper is offered only from here: launchd starts it from
    /// inside the app, and a copy in Downloads or on a disk image moves away.
    static var isInSystemApplications: Bool {
        Bundle.main.bundleURL.standardizedFileURL.path.hasPrefix("/Applications/")
    }

    /// Where the app runs from, as far as the offer to move it goes.
    enum Location: Equatable {
        /// In a system or user Applications folder.
        case installed
        /// On a mounted disk image, or on the random read-only path where
        /// Gatekeeper runs a quarantined download. The real location is
        /// unknown there and the original cannot be trashed, so the app
        /// cannot move itself.
        case cannotMove
        case elsewhere
    }

    static func location(of path: String, home: String = NSHomeDirectory()) -> Location {
        if path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/") { return .installed }
        if path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/") { return .cannotMove }
        return .elsewhere
    }

    static let dragTitle = "Move agent caffeine to the Applications folder"
    static let dragText = "Drag agent caffeine to the Applications folder, then open it from there."
    static let dragQuit = "Quit"
    static let dragContinue = "Continue anyway"

    static func offerToMoveIfNeeded() {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL

        switch location(of: bundleURL.path) {
        case .installed:
            return
        case .cannotMove:
            // Without this the setup window says the app is ready, while
            // the helper, the login item and the hooks need the copy in
            // the Applications folder.
            let alert = NSAlert()
            alert.messageText = dragTitle
            alert.informativeText = dragText
            alert.addButton(withTitle: dragQuit)
            alert.addButton(withTitle: dragContinue)
            alert.alertStyle = .informational
            if alert.runModal() == .alertFirstButtonReturn { NSApp.terminate(nil) }
            return
        case .elsewhere:
            break
        }

        if UserDefaults.standard.bool(forKey: declinedKey) { return }

        let alert = NSAlert()
        alert.messageText = "Move agent caffeine to Applications?"
        alert.informativeText = "agent caffeine is running from \(bundleURL.deletingLastPathComponent().path). Move it to the Applications folder so it stays in one place and updates install cleanly."
        alert.addButton(withTitle: "Move")
        alert.addButton(withTitle: "Not now")
        alert.alertStyle = .informational

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            relocate(from: bundleURL)
        } else {
            UserDefaults.standard.set(true, forKey: declinedKey)
        }
    }

    private static func relocate(from sourceURL: URL) {
        let appName = sourceURL.lastPathComponent
        let destURL = URL(fileURLWithPath: "/Applications").appendingPathComponent(appName)
        let fm = FileManager.default

        do {
            // Copy next to the destination first so an existing install is
            // only replaced once the new copy is complete.
            let tempDir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destURL, create: true)
            let tempURL = tempDir.appendingPathComponent(appName)
            defer { try? fm.removeItem(at: tempDir) }
            try fm.copyItem(at: sourceURL, to: tempURL)
            if fm.fileExists(atPath: destURL.path) {
                _ = try fm.replaceItemAt(destURL, withItemAt: tempURL)
            } else {
                try fm.moveItem(at: tempURL, to: destURL)
            }
        } catch {
            log.error("relocate failed: \(error.localizedDescription, privacy: .public)")
            showError("agent caffeine could not be copied to the Applications folder: \(error.localizedDescription). Drag it there yourself.")
            return
        }

        // Move the original to the trash (best effort; ignore failures).
        try? fm.trashItem(at: sourceURL, resultingItemURL: nil)

        // Relaunch the installed copy and quit this one.
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [destURL.path]
        try? task.run()
        NSApp.terminate(nil)
    }

    private static func showError(_ msg: String) {
        let alert = NSAlert()
        alert.messageText = "agent caffeine could not be moved"
        alert.informativeText = msg
        alert.alertStyle = .warning
        alert.runModal()
    }
}
