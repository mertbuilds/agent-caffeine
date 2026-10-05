import AppKit
import Foundation
import os

enum AppRelocator {
    private static let declinedKey = "AppRelocator.userDeclined"
    private static let log = Logger(subsystem: "com.caffeinagent.app", category: "AppRelocator")

    static func offerToMoveIfNeeded() {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        let path = bundleURL.path

        // Already installed in a system or user Applications folder.
        if path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/") {
            return
        }

        // Running from a mounted disk image. The user will eject it after install,
        // so there is no need to prompt.
        if path.hasPrefix("/Volumes/") {
            return
        }

        // Gatekeeper runs a quarantined download from a random read-only path,
        // so the real location is unknown and the original cannot be trashed.
        if path.contains("/AppTranslocation/") {
            return
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
        alert.messageText = "Move failed"
        alert.informativeText = msg
        alert.alertStyle = .warning
        alert.runModal()
    }
}
