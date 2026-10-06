import CoreGraphics

/// How the sessions of one group stand: each on one line, the name at the
/// leading edge and the state at the trailing edge, or each on two lines,
/// the state below the name. One session that does not fit on one line
/// puts all of them on two, so the group has one shape.
enum ChildLayout: Hashable {
    case oneLine
    case twoLines

    /// The measured texts of one session.
    struct Widths: Equatable {
        var label: CGFloat
        var detail: CGFloat
    }

    static func decide(_ children: [Widths], gap: CGFloat, available: CGFloat) -> ChildLayout {
        children.contains { $0.label + gap + $0.detail > available } ? .twoLines : .oneLine
    }

    /// The state with room for a duration that grows: a number of one
    /// digit is measured as two, so "9 minutes" that becomes "10 minutes"
    /// does not change the shape of the group. A duration in hours and
    /// minutes is measured in its longest form, "1 hour 59 minutes", so
    /// "1 hour" that becomes "1 hour 1 minute" does not either.
    static func reserved(_ text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var result: [String] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            let unit = index + 1 < words.count ? words[index + 1] : ""
            if word.count == 1, word.allSatisfy(\.isNumber), unit == "hour" || unit == "hours" {
                result.append("\(word) hours 59 minutes")
                index += 2
                if index + 1 < words.count, words[index].allSatisfy(\.isNumber), ["minute", "minutes"].contains(words[index + 1]) { index += 2 }
            } else if word == "1", let plural = ["minute": "minutes", "hour": "hours", "day": "days"][unit] {
                result += ["11", plural]
                index += 2
            } else {
                result.append(twoDigits(word))
                index += 1
            }
        }
        return result.joined(separator: " ")
    }

    private static func twoDigits(_ text: String) -> String {
        var result = ""
        var run = ""
        func close() {
            result += run.count == 1 ? run + run : run
            run = ""
        }
        for character in text {
            if character.isNumber {
                run.append(character)
            } else {
                close()
                result.append(character)
            }
        }
        close()
        return result
    }
}
