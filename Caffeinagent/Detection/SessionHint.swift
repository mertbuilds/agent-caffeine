import Darwin
import Foundation

/// What tells two sessions of one agent apart in the menu. A session name
/// can come from what the user typed, so it is shown on this Mac and goes
/// nowhere else: it is not `Codable`, it is not part of the evidence, and
/// it prints as nothing.
struct SessionHint: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    /// The name the agent gave its session.
    var name: String?
    /// The short name of the terminal, as in "ttys004".
    var terminal: String?

    var isEmpty: Bool { name == nil && terminal == nil }

    var description: String { "SessionHint" }
    var debugDescription: String { description }

    static let nameLimit = 60

    /// One line, without the edges, and nil when nothing is left.
    static func cleaned(name: String?) -> String? {
        guard let name else { return nil }
        let words = name.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let line = String(words.joined(separator: " ").prefix(nameLimit))
        return line.isEmpty ? nil : line
    }

    /// Nil for a process without a terminal.
    static func terminalName(device: Int32) -> String? {
        guard device != ProcessInfoRow.noTTY, let name = devname(dev_t(device), S_IFCHR) else { return nil }
        return String(cString: name)
    }
}
