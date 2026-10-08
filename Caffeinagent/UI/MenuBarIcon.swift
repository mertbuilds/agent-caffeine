import AppKit

/// The robot of the app icon, small, for the menu bar: the head with its
/// ear pads, the antenna with its ball, the visor and the eyes. Drawn as
/// vector on a 21 x 20 point canvas (origin top left) whose edges lie on
/// whole points, so they are sharp at 1x and 2x. The template flag lets
/// macOS tint it for light and dark menu bars and the selected state.
///
/// The head is 17 x 14 points, 21 wide with the ear pads, and the visor
/// in it is 13 x 8. The ball of the antenna is 3 points and 1 point of
/// stem shows under it. The eyes are 3 points wide, 3 points to each
/// side of the middle line at x 10.5.
///
/// The drawing takes the top 18 points. The menu bar centres the canvas,
/// so the 2 empty points below the drawing lift it by 1 point: the middle
/// of the head (y 11) sits 1 point under the middle of the bar and the
/// antenna stands above the line the other icons sit on. Set by eye on a
/// real menu bar.
enum MenuBarIcon {
    static let size = NSSize(width: 21, height: 20)

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

    /// Every state has the outline head, and the eyes alone tell the state.
    /// Off: the head is solid while the Mac is kept awake (`MenuBarLook.solid`).
    static let outlineAlways = true

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
        // Can sleep and paused are grey like off: the app holds nothing in all three.
        context.setAlpha(look.opacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { context.endTransparencyLayer() }
        context.setFillColor(ink)
        context.setStrokeColor(ink)

        let head = CGRect(x: 2, y: 4, width: 17, height: 14)
        let visor = CGRect(x: 4, y: 7, width: 13, height: 8)
        // The ball of the antenna and its stem. The stem starts at the
        // middle of the ball and ends inside the head, so no seam shows
        // where a round edge meets a straight one.
        context.fillEllipse(in: CGRect(x: 9, y: 0, width: 3, height: 3))
        context.fill(CGRect(x: 10, y: 1.5, width: 1, height: 3))
        // The ear pads reach out from behind the head.
        for x in [0.0, 18.0] { fill(CGRect(x: x, y: 8.5, width: 3, height: 5), radius: 1.5, in: context) }

        if look.solid && !outlineAlways {
            fill(head, radius: 6, in: context)
            context.setBlendMode(.destinationOut)
            fill(visor, radius: 4, in: context)
            context.setBlendMode(.normal)
        } else {
            // The inside of the head is empty, also where the ear pads began.
            context.setBlendMode(.destinationOut)
            fill(head, radius: 6, in: context)
            context.setBlendMode(.normal)
            context.setLineWidth(1)
            context.addPath(CGPath(roundedRect: head.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 5.5, cornerHeight: 5.5, transform: nil))
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
        for x in [6.0, 12.0] {
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
                context.fill(CGRect(x: x == 6 ? 7 : 12, y: 10, width: 2, height: 2))
            case .open:
                context.fillEllipse(in: CGRect(x: x + 0.25, y: 9.75, width: 2.5, height: 2.5))
            case .closed:
                context.fill(CGRect(x: x, y: onPixels ? 11 : 10.5, width: 3, height: 1))
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
