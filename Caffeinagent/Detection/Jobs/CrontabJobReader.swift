import Foundation

/// Finds the jobs of the crontab of the user, from what `crontab -l`
/// prints.
///
/// Of each line the five time fields are kept, and the name of the
/// command: the first word, without its folder and without any argument.
/// The rest of the line is dropped while the line is read. It can hold a
/// token or a password.
///
/// Skipped: comments, empty lines, lines that set a variable
/// (`NAME=value`), `@reboot`, which has no time, and lines with six time
/// fields. A sixth field is seconds or a year in other dialects, and the
/// five first fields would then give a wrong time.
struct CrontabJobReader {
    static let commandLimit = 40

    func read(_ access: JobSourceAccess) -> JobSourceReading {
        switch access.crontab() {
        case .found(let text): return JobSourceReading(source: .crontab, jobs: Self.jobs(text))
        case .missing: return JobSourceReading(source: .crontab, jobs: [])
        case .failed(let reason): return JobSourceReading(source: .crontab, unreadable: reason)
        }
    }

    /// What a run of `/usr/bin/crontab -l` means. A user with no crontab
    /// gets an exit code that is not 0 and "no crontab for" on the error
    /// output, and that is no failure. The error output is never passed on.
    static func output(status: Int32, stdout: String, stderr: String) -> JobSourceRead<String> {
        if status == 0 { return .found(stdout) }
        if stderr.lowercased().contains("no crontab for") { return .missing }
        return .failed("crontab ended with code \(status)")
    }

    static func jobs(_ text: String) -> [ScheduledJob] {
        var jobs: [ScheduledJob] = []
        var number = 0
        for line in text.components(separatedBy: .newlines) {
            guard let (expression, command) = split(line) else { continue }
            number += 1
            let name = name(ofCommand: command, number: number)
            let base = "crontab:\(expression.key):\(name)"
            let same = jobs.filter { $0.id == base || $0.id.hasPrefix(base + "#") }.count
            jobs.append(ScheduledJob(id: same == 0 ? base : "\(base)#\(same + 1)", source: .crontab, name: name, schedule: .cron(expression)))
        }
        return jobs
    }

    /// The times and the command of a job line, nil for any other line.
    static func split(_ line: String) -> (CronExpression, command: Substring)? {
        let blank: (Character) -> Bool = { $0 == " " || $0 == "\t" }
        var rest = line.drop(while: blank)
        guard let first = rest.first, first != "#", !setsVariable(rest) else { return nil }
        var fields: [Substring] = []
        let count = first == "@" ? 1 : CronExpression.fieldCount
        while fields.count < count {
            let field = rest.prefix(while: { !blank($0) })
            guard !field.isEmpty else { return nil }
            fields.append(field)
            rest = rest.dropFirst(field.count).drop(while: blank)
        }
        guard !rest.isEmpty, let expression = CronExpression.parse(fields.joined(separator: " ")) else { return nil }
        if first != "@", looksLikeATimeField(rest.prefix(while: { !blank($0) })) { return nil }
        return (expression, rest)
    }

    /// `NAME=value` and `NAME = value`.
    private static func setsVariable(_ line: Substring) -> Bool {
        let name = line.prefix(while: { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") })
        guard let first = name.first, !first.isNumber else { return false }
        return line.dropFirst(name.count).drop(while: { $0 == " " || $0 == "\t" }).first == "="
    }

    /// True for the first word of a command that reads as one more time
    /// field: `*/5`, `1-5`, `2026`, `?`, `MON`.
    static func looksLikeATimeField(_ word: Substring) -> Bool {
        let names: Set<String> = [
            "sun", "mon", "tue", "wed", "thu", "fri", "sat",
            "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
        ]
        let parts = word.lowercased().split(whereSeparator: { $0 == "," || $0 == "-" || $0 == "/" })
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { part in
            if names.contains(String(part)) || part == "l" { return true }
            // "15w" and "5l" of other dialects. A command can be named `w`.
            let digits = part.last == "w" || part.last == "l" ? part.dropLast() : part
            return !digits.isEmpty && digits.allSatisfy { $0.isASCII && ($0.isNumber || "*?#".contains($0)) }
        }
    }

    /// "backup.sh" for "~/bin/backup.sh --key abc": the first word without
    /// its folder. "cron job 3" when that word is not a plain file name,
    /// because it can then hold anything: a variable that is set in front
    /// of the command (`TOKEN=abc run`), a quote, a `$`, a pipe.
    static func name(ofCommand command: Substring, number: Int) -> String {
        let fallback = "cron job \(number)"
        let word = command.prefix(while: { $0 != " " && $0 != "\t" })
        let plain: (Character) -> Bool = { $0.isASCII && ($0.isLetter || $0.isNumber || "._+-_".contains($0)) }
        guard word.allSatisfy({ plain($0) || $0 == "/" || $0 == "~" }) else { return fallback }
        let base = (String(word) as NSString).lastPathComponent
        guard !base.isEmpty, base.count <= commandLimit, base.allSatisfy(plain), base.contains(where: \.isLetter) else { return fallback }
        return base
    }
}
