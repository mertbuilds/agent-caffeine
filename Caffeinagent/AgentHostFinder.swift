import AppKit

/// What the aggregator finds the app of an agent through, and brings it
/// to the front. The smoke test has none.
@MainActor
protocol AgentHostFinding: AnyObject {
    /// One answer for each agent, in the order asked.
    func hosts(of agents: [(pid: Int32, kind: AgentDefinition.Kind)]) -> [AgentHost?]
    /// The name of an app as the Dock shows it.
    func name(ofApp pid: Int32) -> String?
    /// False when the app is gone or macOS refuses.
    func bringForward(app pid: Int32) -> Bool
}

/// Reads the process table and the running apps of this Mac.
@MainActor
final class SystemAgentHosts: AgentHostFinding {
    /// One pass asks about the same terminal many times.
    private final class Apps: AgentHostApps {
        private var known: [Int32: Bool] = [:]

        func isRegularApp(_ pid: Int32) -> Bool {
            if let answer = known[pid] { return answer }
            let answer = SystemAgentHosts.regularApp(pid) != nil
            known[pid] = answer
            return answer
        }
    }

    /// Its own, so it keeps what it read of each process between two reads.
    private let census = SystemProcessCensus()

    func hosts(of agents: [(pid: Int32, kind: AgentDefinition.Kind)]) -> [AgentHost?] {
        let apps = Apps()
        // One read of the table for all of them. A process of another
        // user is not in it, as `login` above a shell, and is read alone.
        let rows = census.snapshot() ?? []
        let index = Dictionary(rows.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var others: [Int32: ProcessInfoRow?] = [:]
        let table = AgentHostTable(row: { pid in
            if let row = index[pid] { return row }
            if let known = others[pid] { return known }
            let row = SystemProcessCensus.row(of: pid)
            others.updateValue(row, forKey: pid)
            return row
        }, all: { rows })
        return agents.map { AgentHostResolver.resolve(pid: $0.pid, kind: $0.kind, table: table, apps: apps) }
    }

    func name(ofApp pid: Int32) -> String? {
        Self.regularApp(pid)?.localizedName
    }

    /// The app comes to the front with the window it had in front. Which
    /// window or tab holds the agent is not known here: see `AgentHost`.
    func bringForward(app pid: Int32) -> Bool {
        guard let app = Self.regularApp(pid) else { return false }
        if app.isHidden { app.unhide() }
        let activated: Bool
        if #available(macOS 14.0, *) {
            // From macOS 14 an app comes to the front when the active app
            // gives way to it. A click on the menu or on a notification
            // made agent caffeine the app the user works with.
            NSApp.yieldActivation(to: app)
            activated = app.activate(from: .current, options: [])
        } else {
            activated = app.activate(options: [.activateIgnoringOtherApps])
        }
        if activated { return true }
        // As a click on its icon in the Dock.
        guard let url = app.bundleURL else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return true
    }

    private nonisolated static func regularApp(_ pid: Int32) -> NSRunningApplication? {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated, app.activationPolicy == .regular else { return nil }
        return app
    }
}
