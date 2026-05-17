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

        // Running from a mounted disk image — the user will eject it after install,
        // no need to prompt.
        if path.hasPrefix("/Volumes/") {
            return
        }

        if UserDefaults.standard.bool(forKey: declinedKey) { return }

        let alert = NSAlert()
        alert.messageText = "move caffeinagent to /applications?"
        alert.informativeText = "you’re running caffeinagent from \(bundleURL.deletingLastPathComponent().path). moving it to /applications keeps things tidy and lets future updates land cleanly."
        alert.addButton(withTitle: "move")
        alert.addButton(withTitle: "not now")
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
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: sourceURL, to: destURL)
        } catch {
            log.error("relocate failed: \(error.localizedDescription, privacy: .public)")
            showError("couldn’t write to /applications: \(error.localizedDescription). drag caffeinagent there manually.")
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
        alert.messageText = "move failed"
        alert.informativeText = msg
        alert.alertStyle = .warning
        alert.runModal()
    }
}
