import Foundation

/// The app an agent is shown in: its own app, or the terminal or editor
/// its command line runs in. A click on the agent brings this app to the
/// front.
///
/// That is the app, not the window or the tab. For the exact tab the two
/// terminal devices below are the way in: Terminal and iTerm2 give the
/// `tty` of each tab over Apple events, which needs the Automation
/// permission for that app. The other terminals give none, so they need
/// the Accessibility permission or their own command line.
struct AgentHost: Equatable {
    var appPid: Int32
    /// The terminal device the agent runs on, as in `ProcessInfoRow.tty`.
    /// Nil for a desktop app. Under tmux or herdr this is a pane, not a tab.
    var tty: Int32?
    /// Under tmux or herdr, the terminal device of the client that shows
    /// the session: the tab of the terminal. Nil when more than one client
    /// is in that app.
    var clientTTY: Int32?
}

/// Says which processes are apps with windows. The real one asks
/// `NSRunningApplication`.
protocol AgentHostApps {
    func isRegularApp(_ pid: Int32) -> Bool
}

/// The process table the resolver reads.
struct AgentHostTable {
    /// One process, also one of another user: `login` above a shell
    /// belongs to root.
    var row: (Int32) -> ProcessInfoRow?
    /// Every process of the user. Read only when the way up finds no app.
    var all: () -> [ProcessInfoRow]

    init(row: @escaping (Int32) -> ProcessInfoRow?, all: @escaping () -> [ProcessInfoRow]) {
        self.row = row
        self.all = all
    }

    init(rows: [ProcessInfoRow]) {
        let index = Dictionary(rows.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        self.init(row: { index[$0] }, all: { rows })
    }
}

/// Finds the app of an agent. Pure: the caller passes the process table
/// and what is an app.
enum AgentHostResolver {
    static let deepest = 32

    /// Nil for an agent that is gone, and for one with no app above it:
    /// over SSH, under screen or zellij, or under a tmux or herdr whose
    /// clients are in no app or in more than one.
    static func resolve(pid: Int32, kind: AgentDefinition.Kind, table: AgentHostTable, apps: AgentHostApps) -> AgentHost? {
        guard let agent = table.row(pid) else { return nil }
        let tty = kind == .cli && agent.hasTTY ? agent.tty : nil
        let chain = chain(from: agent, table: table)
        // The binary of a command line agent can lie in the bundle of its
        // desktop app. That says nothing about where it runs.
        if let app = app(above: chain, skippingFirstBundle: kind == .cli, table: table, apps: apps) {
            return AgentHost(appPid: app, tty: tty)
        }
        guard let server = chain.first(where: isServer) else { return nil }
        var clients: [Int32: [ProcessInfoRow]] = [:]
        for client in table.all() where isClient(client) && program(client) == program(server) {
            if let app = app(above: self.chain(from: client, table: table), skippingFirstBundle: true, table: table, apps: apps) {
                clients[app, default: []].append(client)
            }
        }
        guard clients.count == 1, let (app, rows) = clients.first else { return nil }
        return AgentHost(appPid: app, tty: tty, clientTTY: rows.count == 1 ? rows[0].tty : nil)
    }

    /// The process and what is above it, up to launchd.
    private static func chain(from start: ProcessInfoRow, table: AgentHostTable) -> [ProcessInfoRow] {
        var chain = [start]
        while chain.count < deepest, let last = chain.last, last.ppid > 1, last.ppid != last.pid, let next = table.row(last.ppid) {
            chain.append(next)
        }
        return chain
    }

    /// The first app with windows on the way up. Else the app of the first
    /// process that belongs to one: a helper of an app whose parent is
    /// launchd, or the server iTerm2 keeps its shells under.
    private static func app(above chain: [ProcessInfoRow], skippingFirstBundle: Bool, table: AgentHostTable, apps: AgentHostApps) -> Int32? {
        if let app = chain.first(where: { apps.isRegularApp($0.pid) }) { return app.pid }
        for row in chain.dropFirst(skippingFirstBundle ? 1 : 0) {
            guard let isMain = mainExecutable(ofAppOf: row.executablePath) else { continue }
            let mains = table.all().filter { isMain($0.executablePath) && apps.isRegularApp($0.pid) }
            if mains.isEmpty { continue }
            // Two copies of the app run: which one is not known.
            return mains.count == 1 ? mains[0].pid : nil
        }
        return nil
    }

    /// Says whether a path is the main executable of the app that this
    /// executable belongs to. Nil for an executable of no app. A helper
    /// app lies inside the app, so the first bundle of the path is the app.
    static func mainExecutable(ofAppOf path: String) -> ((String) -> Bool)? {
        if let bundle = path.range(of: ".app/Contents/") {
            let prefix = path[..<bundle.upperBound] + "MacOS/"
            return { $0.hasPrefix(prefix) }
        }
        // iTerm2 starts its shells under a server that outlives the app.
        // The server lies in Application Support and its parent is launchd.
        if (path as NSString).lastPathComponent.hasPrefix("iTermServer") {
            return { $0.hasSuffix("/iTerm.app/Contents/MacOS/iTerm2") }
        }
        return nil
    }

    /// The multiplexers whose clients are processes of their own with the
    /// terminal of their tab: tmux, and herdr, which has the same shape.
    /// screen and zellij are not read.
    static let multiplexers: Set<String> = ["tmux", "herdr"]

    private static func program(_ row: ProcessInfoRow) -> String {
        (row.executablePath as NSString).lastPathComponent
    }

    private static func isMultiplexer(_ row: ProcessInfoRow) -> Bool {
        multiplexers.contains(program(row))
    }

    /// The server has no terminal. A client has the one of its tab.
    private static func isServer(_ row: ProcessInfoRow) -> Bool {
        isMultiplexer(row) && !row.hasTTY
    }

    private static func isClient(_ row: ProcessInfoRow) -> Bool {
        isMultiplexer(row) && row.hasTTY
    }
}

/// How to go to the app of an agent. Pure: the caller passes what the
/// system says of the running app.
enum AgentHostReveal: Equatable {
    /// Open the bundle of the running app, as a click on its icon in the
    /// Dock: the app then shows a window that is in the Dock, or makes one
    /// when it has none.
    case open(bundle: URL)
    /// The app has no bundle to open. It comes to the front with the
    /// windows it has on screen.
    case activate

    private static let executables = ".app/Contents/MacOS/"

    /// - Parameters:
    ///   - bundleURL: what the running app gives as its bundle. For an
    ///     executable that is in no bundle this is not an app.
    ///   - executableURL: the binary of the running app. An app started
    ///     from a command line still lies in its bundle.
    static func way(bundleURL: URL?, executableURL: URL?) -> AgentHostReveal {
        if let bundleURL, bundleURL.pathExtension == "app" { return .open(bundle: bundleURL) }
        // The bundle the binary lies in, not one that bundle lies in. To
        // open the binary itself would start a second copy.
        if let path = executableURL?.path, let inner = path.range(of: executables, options: .backwards) {
            let bundle = String(path[..<inner.lowerBound]) + ".app"
            return .open(bundle: URL(fileURLWithPath: bundle, isDirectory: true))
        }
        return .activate
    }
}
