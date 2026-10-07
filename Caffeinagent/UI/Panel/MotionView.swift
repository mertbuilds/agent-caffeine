import AppKit
import SwiftUI

/// A view of layers that Core Animation moves. The render server runs the
/// loops, so the app does no work for a frame. A click goes through to
/// what is below.
class MotionView: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Pixels per point of the screen the view is on.
    var scale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    /// Changes layers at once: a layer of its own would fade to each new
    /// value otherwise.
    func withoutActions(_ change: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        change()
        CATransaction.commit()
    }
}

extension CALayer {
    private static let loopPrefix = "loop."
    private static let stateKey = "state."

    /// Runs a track on a property for ever. The loop is in step with the
    /// clock of Core Animation and not with the moment it starts, so it
    /// goes on where it would be when it is put on again.
    func loop(_ track: MotionTrack, on keyPath: String, _ value: (Double) -> Any = { $0 }) {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = track.values.map(value)
        animation.keyTimes = track.keyTimes.map { NSNumber(value: $0) }
        animation.calculationMode = .linear
        animation.duration = track.period
        animation.repeatCount = .infinity
        animation.beginTime = convertTime(track.start, from: nil)
        add(animation, forKey: Self.loopPrefix + keyPath)
    }

    /// Runs an animation for ever, under the name of its property.
    func loop(_ animation: CAPropertyAnimation) {
        animation.repeatCount = .infinity
        add(animation, forKey: Self.loopPrefix + (animation.keyPath ?? ""))
    }

    /// Takes every loop off this layer and the layers in it.
    func endLoops() {
        for key in animationKeys() ?? [] where key.hasPrefix(Self.loopPrefix) { removeAnimation(forKey: key) }
        for layer in sublayers ?? [] { layer.endLoops() }
    }

    /// Shows or hides the layer, with the spring of a change of state.
    func fade(to value: Float, animated: Bool) {
        guard opacity != value else { return }
        if animated {
            let spring = CASpringAnimation(keyPath: "opacity")
            spring.fromValue = presentation()?.opacity ?? opacity
            spring.toValue = value
            let (response, dampingFraction) = PanelMetrics.stateChangeSpring
            spring.mass = 1
            spring.stiffness = pow(2 * .pi / response, 2)
            spring.damping = 4 * .pi * dampingFraction / response
            spring.duration = spring.settlingDuration
            add(spring, forKey: Self.stateKey + "opacity")
        } else {
            removeAnimation(forKey: Self.stateKey + "opacity")
        }
        opacity = value
    }

    /// A picture as the contents, in points of the layer above.
    func show(_ image: CGImage, in frame: CGRect) {
        contents = image
        bounds = CGRect(origin: .zero, size: frame.size)
        position = CGPoint(x: frame.minX + anchorPoint.x * frame.width, y: frame.minY + anchorPoint.y * frame.height)
    }
}
