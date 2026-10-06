import AppKit

/// How wide a text of the menu is, to know the height of the list before
/// the layout: two texts that do not fit side by side take two lines.
enum TextFit {
    /// - Parameter digits: the text has digits of one width, as a
    ///   duration that counts has.
    static func width(_ text: String, style: NSFont.TextStyle, digits: Bool = false) -> CGFloat {
        let size = NSFont.preferredFont(forTextStyle: style).pointSize
        let font = digits ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular) : NSFont.systemFont(ofSize: size)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}
