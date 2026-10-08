import Foundation

/// A hold that a script, a long job or an agent asked for through the
/// command line tool or its MCP server: one file in the holds folder,
/// `<id>.json`. It is evidence of work like an agent, and `HoldPolicy`
/// decides what it is worth, so every stop still wins.
///
/// A hold can never keep the Mac awake for longer than it says: a timed
/// hold ends at its time, and a command hold ends with the process that
/// holds it, at the latest after `commandCap`.
struct ManualHold: Codable, Equatable, Identifiable {
    static let currentVersion = 1
    /// What `hold` asks for with no `--for`.
    static let defaultLength: TimeInterval = 3600
    /// No timed hold lasts longer.
    static let timedCap: TimeInterval = 12 * 3600
    /// No command holds for longer. The command itself runs on.
    static let commandCap: TimeInterval = 24 * 3600
    static let reasonLimit = 80
    static let commandLimit = 40
    static let idLimit = 32
    /// Two readings of one start time can differ in the last digit.
    static let startTolerance: TimeInterval = 0.001
    /// A hold that begins further ahead of the clock than this was made
    /// before the clock was set back, and its end means nothing now.
    static let clockTolerance: TimeInterval = 60

    enum Kind: String, Codable {
        /// Until a time of day.
        case timed
        /// While the process that holds it runs.
        case command
    }

    var v = ManualHold.currentVersion
    var id: String
    var kind: Kind
    /// The process that holds a command hold: the command line tool that
    /// runs the command and waits for it.
    var pid: Int32?
    /// Start time of that process, as in `ProcessInfoRow`: a pid is used
    /// again after its process exits.
    var pidStart: TimeInterval?
    /// Seconds since the epoch.
    var start: TimeInterval
    var end: TimeInterval
    /// What the caller said it is for. One line, see `clean`.
    var reason: String?
    /// The name of the command of a command hold, without its folder and
    /// its arguments.
    var command: String?

    static func timed(id: String = newID(), length: TimeInterval, reason: String? = nil, now: Date) -> ManualHold {
        let start = now.timeIntervalSince1970
        return ManualHold(id: id, kind: .timed, start: start, end: start + length, reason: clean(reason, limit: reasonLimit))
    }

    static func command(
        id: String = newID(), holder: ProcessIdentity, command: String, reason: String? = nil, now: Date
    ) -> ManualHold {
        let start = now.timeIntervalSince1970
        return ManualHold(
            id: id, kind: .command, pid: holder.pid, pidStart: holder.startTime, start: start, end: start + commandCap,
            reason: clean(reason, limit: reasonLimit), command: commandName(command)
        )
    }

    var cap: TimeInterval { kind == .timed ? Self.timedCap : Self.commandCap }
    var endsAt: Date { Date(timeIntervalSince1970: end) }
    var startedAt: Date { Date(timeIntervalSince1970: start) }

    /// The title of its line in the menu.
    var title: String { reason ?? command ?? "Command line" }
    /// Who asked, for the headline: "ffmpeg asked for it".
    var subject: String { reason ?? command ?? "A command" }

    /// The time alone: the hold has not ended, and neither its length nor
    /// what is left of it is above the cap. An end that is further away
    /// means the clock was set back, and the hold is over. A reader that
    /// took its time just before the hold was written sees a hold of the
    /// full cap end a moment further away, so the same tolerance counts.
    func isTimely(now: Date) -> Bool {
        let time = now.timeIntervalSince1970
        guard v == Self.currentVersion, start.isFinite, end.isFinite, Self.isValidID(id) else { return false }
        return time < end && end - time <= cap + Self.clockTolerance && end - start <= cap && start - time <= Self.clockTolerance
    }

    /// True for a timed hold, which no process holds. A command hold
    /// lives while its holder does, with the same start time.
    /// - Parameter startTime: of a process that runs now, nil when it is gone.
    func holderIsAlive(startTime: (Int32) -> TimeInterval?) -> Bool {
        guard kind == .command else { return true }
        guard let pid, pid > 1, let pidStart, let running = startTime(pid) else { return false }
        return abs(running - pidStart) <= Self.startTolerance
    }

    /// True for a command hold whose holder a signal stopped, as with
    /// `kill -STOP` or Ctrl-Z: the tool waits for nothing while it is
    /// stopped, so the hold does not count until it is continued.
    func holderIsStopped(_ stopped: (Int32) -> Bool) -> Bool {
        guard kind == .command, let pid else { return false }
        return stopped(pid)
    }

    /// As it is taken from a file: the texts cut and cleaned again, so a
    /// file that was written by hand shows nothing the tool would refuse.
    var cleaned: ManualHold {
        var hold = self
        hold.reason = Self.clean(reason, limit: Self.reasonLimit)
        hold.command = Self.clean(command, limit: Self.commandLimit)
        return hold
    }

    // MARK: Texts

    static func newID() -> String {
        let hex = String(UInt32.random(in: .min ... .max), radix: 16)
        return String(repeating: "0", count: 8 - hex.count) + hex
    }

    /// The id is a file name, so it holds lower case letters and digits only.
    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= idLimit && id.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("0"..."9").contains($0)
        }
    }

    /// One line of at most `limit` characters: control characters and line
    /// breaks become spaces, and runs of spaces become one. Nil when
    /// nothing is left.
    static func clean(_ text: String?, limit: Int) -> String? {
        guard let text else { return nil }
        let plain = String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) ? " " : scalar
        }))
        let words = plain.split(whereSeparator: { $0 == " " || $0 == "\u{00A0}" })
        let line = String(words.joined(separator: " ").prefix(limit)).trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? nil : line
    }

    /// "ffmpeg" for "/opt/homebrew/bin/ffmpeg".
    static func commandName(_ command: String) -> String? {
        clean((command as NSString).lastPathComponent, limit: commandLimit)
    }
}

/// The length of a hold as the command line takes it: `90s`, `30m`, `2h`,
/// or parts of these in a row, as in `1h30m`.
enum HoldDuration {
    /// Nil for a text that is no length, and for a length of zero.
    static func parse(_ text: String) -> TimeInterval? {
        var total: TimeInterval = 0
        var digits = ""
        var parts = 0
        for character in text.lowercased() {
            if character.isASCII, character.isNumber {
                digits.append(character)
                continue
            }
            // Longer than any length the caps allow.
            guard !digits.isEmpty, digits.count <= 6, let value = TimeInterval(digits) else { return nil }
            switch character {
            case "s": total += value
            case "m": total += value * 60
            case "h": total += value * 3600
            default: return nil
            }
            digits = ""
            parts += 1
        }
        guard digits.isEmpty, parts > 0, total > 0 else { return nil }
        return total
    }
}
