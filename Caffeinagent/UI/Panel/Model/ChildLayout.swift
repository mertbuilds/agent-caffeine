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
    /// does not change the shape of the group.
    static func reserved(_ text: String) -> String {
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
