import AppKit

/// The robot head in the menu bar, drawn as vector on an 18 x 18 point canvas
/// (origin top left). The drawing handler runs at the backing scale of the
/// screen, so edges stay sharp at 1x and 2x, and the template flag lets macOS
/// tint it for light and dark menu bars and the selected state.
enum MenuBarIcon {
    static let held = make(held: true)
    static let notHeld = make(held: false)

    static func make(held: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // The thin antenna adds little weight, so the head reads low when
            // the canvas is centred. Lift it half a point (one pixel at 2x).
            context.translateBy(x: 0, y: -0.5)
            context.setFillColor(NSColor.black.cgColor)
            context.setStrokeColor(NSColor.black.cgColor)
            if held {
                drawAwake(in: context)
            } else {
                drawAsleep(in: context)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityLabel(held: held)
        return image
    }

    static func accessibilityLabel(held: Bool) -> String {
        held ? "agent caffeine, keeping the Mac awake" : "agent caffeine, not keeping the Mac awake"
    }

    private static func drawAwake(in context: CGContext) {
        context.fillEllipse(in: CGRect(x: 9 - 1.35, y: 2.3 - 1.35, width: 2.7, height: 2.7))
        context.fill(CGRect(x: 8.4, y: 3, width: 1.2, height: 2.6))
        for (rect, radius) in [
            (CGRect(x: 2.6, y: 5.2, width: 12.8, height: 10.3), 4.6),
            (CGRect(x: 0.9, y: 8.6, width: 2, height: 3.4), 1),
            (CGRect(x: 15.1, y: 8.6, width: 2, height: 3.4), 1),
        ] {
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        }

        // Smiling eyes, cut out of the head.
        let eyes = CGMutablePath()
        for x in [5.5, 10.0] {
            eyes.move(to: CGPoint(x: x, y: 11.1))
            eyes.addQuadCurve(to: CGPoint(x: x + 2.5, y: 11.1), control: CGPoint(x: x + 1.25, y: 9.0))
        }
        context.setBlendMode(.destinationOut)
        context.setLineWidth(1.35)
        context.setLineCap(.round)
        context.addPath(eyes)
        context.strokePath()
    }

    private static func drawAsleep(in context: CGContext) {
        context.setLineWidth(1.1)
        context.strokeEllipse(in: CGRect(x: 9 - 0.9, y: 2.3 - 0.9, width: 1.8, height: 1.8))
        context.strokeLineSegments(between: [CGPoint(x: 9, y: 3.3), CGPoint(x: 9, y: 5.3)])

        context.setLineWidth(1.25)
        context.addPath(CGPath(roundedRect: CGRect(x: 3.2, y: 5.8, width: 11.6, height: 9.1), cornerWidth: 4, cornerHeight: 4, transform: nil))
        context.strokePath()

        context.setLineCap(.round)
        context.strokeLineSegments(between: [
            CGPoint(x: 1.6, y: 9), CGPoint(x: 1.6, y: 11.6),
            CGPoint(x: 16.4, y: 9), CGPoint(x: 16.4, y: 11.6),
        ])

        // Closed eyes.
        context.setLineWidth(1.3)
        context.strokeLineSegments(between: [
            CGPoint(x: 5.5, y: 10.6), CGPoint(x: 8, y: 10.6),
            CGPoint(x: 10, y: 10.6), CGPoint(x: 12.5, y: 10.6),
        ])
    }
}
