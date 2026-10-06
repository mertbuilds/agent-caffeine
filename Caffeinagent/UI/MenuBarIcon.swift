import AppKit

/// The robot of the app icon, small, for the menu bar: the head with its
/// ear pads, the antenna with its ball, the visor and the eyes. Drawn as
/// vector on a 19 x 18 point canvas (origin top left) whose edges lie on
/// whole points, so they are sharp at 1x and 2x. The template flag lets
/// macOS tint it for light and dark menu bars and the selected state.
enum MenuBarIcon {
    static let size = NSSize(width: 19, height: 18)

    /// A robot that is knocked out gets red crosses for eyes, in a picture
    /// that is no template and takes its ink from the menu bar it is drawn
    /// in. Off: the crosses are in the ink of the menu bar like the rest.
    ///
    /// Checked with a status item on macOS 26: the menu bar extra hands
    /// this very image to its button, the button draws it again under the
    /// appearance of the menu bar when that changes (white ink on a dark
    /// bar, black on a light one), and a highlighted button keeps the
    /// normal background style, so the ink stays.
    static let redCrosses = true

    private static var cache: [MenuBarLook: NSImage] = [:]

    static func image(for look: MenuBarLook) -> NSImage {
        if let image = cache[look] { return image }
        let image = make(look, colored: redCrosses && look.eyes == .dead)
        cache[look] = image
        return image
    }

    static func make(_ look: MenuBarLook, colored: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // A template is tinted by macOS. A picture with colour has to
            // take the ink of the menu bar it is drawn in.
            let ink = colored ? NSColor.labelColor.usingColorSpace(.sRGB)?.withAlphaComponent(1).cgColor ?? NSColor.black.cgColor : NSColor.black.cgColor
            draw(look, in: context, ink: ink, crosses: colored ? NSColor.systemRed.cgColor : ink)
            return true
        }
        image.isTemplate = !colored
        image.accessibilityDescription = look.accessibilityLabel
        return image
    }

    static func draw(_ look: MenuBarLook, in context: CGContext, ink: CGColor, crosses: CGColor) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setAlpha(look.opacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { context.endTransparencyLayer() }
        context.setFillColor(ink)
        context.setStrokeColor(ink)

        let head = CGRect(x: 2, y: 5, width: 15, height: 12)
        let visor = CGRect(x: 4, y: 8, width: 11, height: 6)
        // The ball of the antenna and its stem.
        context.fillEllipse(in: CGRect(x: 8, y: 1, width: 3, height: 3))
        context.fill(CGRect(x: 9, y: 4, width: 1, height: 1))
        // The ear pads reach out from behind the head.
        for x in [0.0, 16.0] { fill(CGRect(x: x, y: 8.5, width: 3, height: 5), radius: 1.5, in: context) }

        if look.solid {
            fill(head, radius: 5, in: context)
            context.setBlendMode(.destinationOut)
            fill(visor, radius: 3, in: context)
            context.setBlendMode(.normal)
        } else {
            // The inside of the head is empty, also where the ear pads began.
            context.setBlendMode(.destinationOut)
            fill(head, radius: 5, in: context)
            context.setBlendMode(.normal)
            context.setLineWidth(1)
            context.addPath(CGPath(roundedRect: head.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 4.5, cornerHeight: 4.5, transform: nil))
            context.strokePath()
        }
        // At 1x the eyes are set on whole pixels.
        drawEyes(look.eyes, in: context, crosses: crosses, onPixels: abs(context.ctm.a) < 1.5)
    }

    /// Two eyes in the visor, each 3 points wide. At 1x a curve of that
    /// size is a smear, so each eye is a few whole pixels there.
    private static func drawEyes(_ eyes: MenuBarLook.Eyes, in context: CGContext, crosses: CGColor, onPixels: Bool) {
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for x in onPixels ? [5.0, 11.0] : [5.5, 10.5] {
            func pixels(_ points: [(CGFloat, CGFloat)]) {
                context.fill(points.map { CGRect(x: x + $0.0, y: 10 + $0.1, width: 1, height: 1) })
            }
            switch eyes {
            case .happy where onPixels:
                pixels([(1, 0), (0, 1), (2, 1)])
            case .happy:
                context.setLineWidth(1.2)
                context.move(to: CGPoint(x: x, y: 12))
                context.addQuadCurve(to: CGPoint(x: x + 3, y: 12), control: CGPoint(x: x + 1.5, y: 8.6))
                context.strokePath()
            case .open where onPixels:
                // Two pixels wide, and the same distance from the middle.
                context.fill(CGRect(x: x == 5 ? 6 : 11, y: 10, width: 2, height: 2))
            case .open:
                context.fillEllipse(in: CGRect(x: x + 0.25, y: 9.75, width: 2.5, height: 2.5))
            case .closed:
                context.fill(CGRect(x: x, y: 11, width: 3, height: 1))
            case .dead where onPixels:
                context.setFillColor(crosses)
                pixels([(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)])
            case .dead:
                context.setStrokeColor(crosses)
                context.setLineWidth(1.1)
                context.strokeLineSegments(between: [
                    CGPoint(x: x + 0.25, y: 9.75), CGPoint(x: x + 2.75, y: 12.25),
                    CGPoint(x: x + 2.75, y: 9.75), CGPoint(x: x + 0.25, y: 12.25),
                ])
            }
        }
    }

    private static func fill(_ rect: CGRect, radius: CGFloat, in context: CGContext) {
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
    }
}
