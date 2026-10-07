import AppKit
import SwiftUI

/// What the layers of the robot show at a moment.
struct RobotScene: Equatable {
    var look: RobotLook
    /// The loops run: the menu is open and motion is allowed.
    var moves: Bool
    /// A fixed moment of the motion, for a still picture of it.
    var frozenTime: TimeInterval?
    /// When the float began, on the clock of Core Animation.
    var floatBegan: CFTimeInterval?
    /// How many blinks the user asked for.
    var taps = 0

    /// How much of the icon's own eyes shows.
    var iconEyes: Float {
        switch look.eyes {
        case .happy: return 1
        case .dim: return 0.3
        case .open, .closed, .dead: return 0
        }
    }

    /// How far the eyes are shut in a still picture.
    var shut: Double {
        guard look.blinks, let frozenTime else { return 0 }
        return Double(RobotBlink.closure(at: frozenTime))
    }

    var floats: Bool {
        moves && look.bob > 0 && floatBegan != nil
    }
}

/// The layers of the robot that float over the tile. Core Animation runs
/// the float and every other loop, and only while the scene moves.
class RobotLayerView: MotionView {
    private static let settleKey = "state.transform"
    private static let tapPrefix = "tap."

    let floating = CALayer()
    private var scene: RobotScene?
    private var drawn: (side: CGFloat, scale: CGFloat)?
    private var lastTap: CFTimeInterval = 0

    override init() {
        super.init()
        layer?.addSublayer(floating)
    }

    func show(_ new: RobotScene) {
        let old = scene
        scene = new
        guard drawn != nil, old != new else { return }
        withoutActions { change(from: old, to: new) }
    }

    override func layout() {
        super.layout()
        let side = bounds.width
        guard side > 0, drawn?.side != side || drawn?.scale != scale else { return }
        drawn = (side, scale)
        withoutActions {
            floating.bounds = bounds
            floating.position = CGPoint(x: bounds.midX, y: bounds.midY)
            build(side: side, scale: scale)
            if let scene { change(from: nil, to: scene) }
        }
    }

    private func change(from old: RobotScene?, to new: RobotScene) {
        let side = bounds.width
        let lifted = floating.presentation()?.transform
        let visible = old != nil && new.moves
        pose(new, animated: visible && old?.look != new.look)
        layer?.endLoops()
        still(new, side: side)
        float(new, side: side, settlingFrom: visible && old?.floats == true ? lifted : nil)
        guard new.moves else { return }
        run(new, side: side)
        if let old, old.taps != new.taps { blinkOnce(new) }
    }

    private func float(_ scene: RobotScene, side: CGFloat, settlingFrom lifted: CATransform3D?) {
        let travel = scene.look.bob * side / (RobotGeometry.points * RobotGeometry.shownScale)
        let rise = scene.look.bob > 0 ? scene.frozenTime.map(RobotFloat.rise(at:)) ?? 0 : 0
        let scale = 1 + RobotFloat.growth * rise
        floating.transform = CATransform3DScale(CATransform3DMakeTranslation(0, -travel * rise, 0), scale, scale, 1)
        if scene.floats, let began = scene.floatBegan {
            floating.removeAnimation(forKey: Self.settleKey)
            for (keyPath, top) in [("transform.scale", 1 + RobotFloat.growth), ("transform.translation.y", -travel)] {
                let way = CABasicAnimation(keyPath: keyPath)
                way.fromValue = keyPath == "transform.scale" ? 1 : 0
                way.toValue = top
                way.duration = RobotFloat.period / 2
                way.autoreverses = true
                let ease = RobotFloat.ease
                way.timingFunction = CAMediaTimingFunction(controlPoints: Float(ease.x1), Float(ease.y1), Float(ease.x2), Float(ease.y2))
                way.beginTime = floating.convertTime(began, from: nil)
                floating.loop(way)
            }
        } else if let lifted {
            let settle = CABasicAnimation(keyPath: "transform")
            settle.fromValue = NSValue(caTransform3D: lifted)
            settle.duration = RobotFloat.settle
            settle.timingFunction = CAMediaTimingFunction(name: .easeOut)
            floating.add(settle, forKey: Self.settleKey)
        }
    }

    /// One blink on a property, from `open` to `shut` and back.
    func tap(_ layer: CALayer, _ keyPath: String, open: Double, shut: Double) {
        let times = RobotBlink.tap
        let whole = times.shut + times.hold + times.open
        let blink = CAKeyframeAnimation(keyPath: keyPath)
        blink.values = [open, shut, shut, open]
        blink.keyTimes = [0, times.shut / whole, (times.shut + times.hold) / whole, 1].map { NSNumber(value: $0) }
        blink.timingFunctions = [CAMediaTimingFunction(name: .easeIn), CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeOut)]
        blink.duration = whole
        layer.add(blink, forKey: Self.tapPrefix + keyPath)
    }

    private func blinkOnce(_ scene: RobotScene) {
        let now = CACurrentMediaTime()
        let times = RobotBlink.tap
        guard now - lastTap > times.shut + times.hold + times.open else { return }
        lastTap = now
        blink(scene)
    }

    // MARK: For the two views

    /// Puts the pictures in the layers. Called again when the size or the
    /// screen changes.
    func build(side: CGFloat, scale: CGFloat) {}

    /// What the pose shows and hides.
    func pose(_ scene: RobotScene, animated: Bool) {}

    /// The values of everything that moves, at the frozen moment or at rest.
    func still(_ scene: RobotScene, side: CGFloat) {}

    /// Starts the loops of the pose.
    func run(_ scene: RobotScene, side: CGFloat) {}

    /// One blink the user asked for.
    func blink(_ scene: RobotScene) {}
}

/// The robot and the eyes of the icon, as pictures.
struct RobotBodyLayers: NSViewRepresentable {
    let scene: RobotScene

    func makeNSView(context: Context) -> RobotBodyView { RobotBodyView() }

    func updateNSView(_ view: RobotBodyView, context: Context) {
        view.show(scene)
    }
}

final class RobotBodyView: RobotLayerView {
    private let body = CALayer()
    /// Shuts the eyes for a blink. The eyes in it fade with the pose.
    private let lids = CALayer()
    private let eyes = CALayer()

    override init() {
        super.init()
        floating.addSublayer(body)
        floating.addSublayer(lids)
        lids.addSublayer(eyes)
    }

    override func build(side: CGFloat, scale: CGFloat) {
        for (layer, name) in [(body, "RobotBody"), (eyes, "RobotEyes")] {
            layer.contents = NSImage(named: name)?.layerContents(forContentsScale: scale)
            layer.contentsScale = scale
        }
        for layer in [body, lids, eyes] { layer.frame = floating.bounds }
    }

    override func pose(_ scene: RobotScene, animated: Bool) {
        eyes.fade(to: scene.iconEyes, animated: animated)
    }

    override func still(_ scene: RobotScene, side: CGFloat) {
        lids.opacity = Float(1 - scene.shut)
    }

    override func run(_ scene: RobotScene, side: CGFloat) {
        if scene.look.blinks, scene.iconEyes > 0 { lids.loop(RobotBlink.track, on: "opacity") { 1 - $0 } }
    }

    override func blink(_ scene: RobotScene) {
        tap(lids, "opacity", open: 1, shut: 0)
    }
}

/// What is drawn over the robot: the eyes the icon does not have, the
/// light of the antenna, the steam and the letters of its sleep.
struct RobotOverlayLayers: NSViewRepresentable {
    let scene: RobotScene

    func makeNSView(context: Context) -> RobotOverlayView { RobotOverlayView() }

    func updateNSView(_ view: RobotOverlayView, context: Context) {
        view.show(scene)
    }
}

final class RobotOverlayView: RobotLayerView {
    private struct Wisp {
        let group = CALayer()
        /// Each copy rises, and the picture in it leans.
        let copies = (0..<RobotSteamMotion.copies).map { _ in (rise: CALayer(), lean: CALayer()) }
    }

    private let openEyes = CALayer()
    private let shutEyes = CALayer()
    /// The shut eyes again, for the blink of the icon's eyes.
    private let blinkEyes = CALayer()
    private let deadEyes = CALayer()
    private let blue = CALayer()
    private let blueHalo = CALayer()
    private let amber = CALayer()
    private let amberHalo = CALayer()
    private let amberBall = CALayer()
    private let red = CALayer()
    private let redHalo = CALayer()
    private let redBall = CALayer()
    private let shade = CALayer()
    private let wisps = RobotWisp.all.map { _ in Wisp() }
    private let snooze = CALayer()
    private let letters = (0..<RobotSnoozeMotion.letters).map { _ in CALayer() }
    /// Where each letter is at the start of its way and at the end.
    private var ways: [(from: CGPoint, to: CGPoint)] = []

    override init() {
        super.init()
        blue.addSublayer(blueHalo)
        amber.addSublayer(amberHalo)
        amber.addSublayer(amberBall)
        red.addSublayer(redHalo)
        red.addSublayer(redBall)
        for layer in [openEyes, shutEyes, blinkEyes, deadEyes, blue, amber, red, shade] { floating.addSublayer(layer) }
        for wisp in wisps {
            floating.addSublayer(wisp.group)
            for copy in wisp.copies {
                wisp.group.addSublayer(copy.rise)
                copy.rise.addSublayer(copy.lean)
            }
        }
        // The letters do not float with the robot.
        layer?.addSublayer(snooze)
        letters.forEach(snooze.addSublayer)
        openEyes.anchorPoint = CGPoint(x: RobotEyes.anchor.x, y: RobotEyes.anchor.y)
        redHalo.opacity = Float(RobotAntennaLight.redStrength)
    }

    override func build(side: CGFloat, scale: CGFloat) {
        func put(_ part: RobotArt.Part, in layers: CALayer...) {
            guard let piece = RobotArt.piece(part, side: side, scale: scale) else { return }
            layers.forEach { $0.show(piece.image, in: piece.frame) }
        }
        put(.openEyes, in: openEyes)
        put(.shutEyes, in: shutEyes, blinkEyes)
        put(.deadEyes, in: deadEyes)
        put(.halo(.blue), in: blueHalo)
        put(.halo(.amber), in: amberHalo)
        put(.ball(.amber), in: amberBall)
        put(.halo(.red), in: redHalo)
        put(.ball(.red), in: redBall)
        put(.shade, in: shade)
        for (index, wisp) in wisps.enumerated() {
            guard let piece = RobotArt.piece(.wisp(index), side: side, scale: scale) else { continue }
            let foot = RobotWisp.all[index].foot
            let anchor = CGPoint(x: (foot.x * side - piece.frame.minX) / piece.frame.width, y: (foot.y * side - piece.frame.minY) / piece.frame.height)
            for copy in wisp.copies {
                copy.rise.anchorPoint = anchor
                copy.rise.bounds = CGRect(origin: .zero, size: piece.frame.size)
                copy.rise.position = CGPoint(x: foot.x * side, y: foot.y * side)
                copy.lean.anchorPoint = anchor
                copy.lean.minificationFilter = .trilinear
                copy.lean.show(piece.image, in: copy.rise.bounds)
            }
        }
        ways = []
        for (index, letter) in letters.enumerated() {
            guard let piece = RobotArt.piece(.snooze(index), side: side, scale: scale) else { continue }
            letter.anchorPoint = .zero
            letter.minificationFilter = .trilinear
            letter.show(piece.image, in: piece.frame)
            func corner(_ phase: Double) -> CGPoint {
                let place = RobotSnoozeMotion.place(letter: index, phase: phase)
                return CGPoint(x: place.x * side + piece.frame.minX, y: place.y * side + piece.frame.minY)
            }
            ways.append((corner(0), corner(1)))
        }
    }

    override func pose(_ scene: RobotScene, animated: Bool) {
        let look = scene.look
        openEyes.fade(to: look.eyes == .open ? 1 : 0, animated: animated)
        shutEyes.fade(to: look.eyes == .closed ? 1 : 0, animated: animated)
        deadEyes.fade(to: look.eyes == .dead ? 1 : 0, animated: animated)
        blue.fade(to: look.antenna == .glowing || look.antenna == .steady ? 1 : 0, animated: animated)
        amber.fade(to: look.antenna == .amber ? 1 : 0, animated: animated)
        red.fade(to: look.antenna == .red ? 1 : 0, animated: animated)
        shade.fade(to: look.antenna == .dark ? 1 : 0, animated: animated)
        for (index, wisp) in wisps.enumerated() {
            wisp.group.fade(to: index < look.wisps ? 1 : 0, animated: animated)
        }
        snooze.fade(to: look.snoozes ? 1 : 0, animated: animated)
    }

    override func still(_ scene: RobotScene, side: CGFloat) {
        let look = scene.look
        let time = scene.frozenTime
        blinkEyes.opacity = look.eyes == .happy ? Float(scene.shut) : 0
        openEyes.transform = CATransform3DMakeScale(1, 1 - (1 - RobotEyes.shutScale) * scene.shut, 1)
        let pulse = time.map(RobotAntennaPulse.track.value(at:)) ?? RobotAntennaPulse.rest
        blueHalo.opacity = Float(RobotAntennaLight.blueStrength(pulse: look.antenna == .glowing ? pulse : RobotAntennaPulse.rest))
        amberHalo.opacity = Float(RobotAntennaLight.amberStrength(pulse: pulse))
        for (index, wisp) in wisps.enumerated() {
            let sway = time.map(RobotSteamMotion.swayTrack(wisp: index).value(at:)) ?? 0
            for (number, copy) in wisp.copies.enumerated() {
                let phase = time.map(RobotSteamMotion.stretchTrack(wisp: index, copy: number).phase(at:)) ?? RobotSteamMotion.restPhase(copy: number)
                copy.rise.transform = CATransform3DScale(
                    CATransform3DMakeTranslation(0, -RobotSteamMotion.lift(phase) * side, 0), 1, RobotSteamMotion.stretch(phase), 1
                )
                copy.rise.opacity = Float(RobotSteamMotion.strength(phase))
                copy.lean.transform = Self.lean(sway, wisp: index)
            }
        }
        for (index, letter) in letters.enumerated() where index < ways.count {
            let phase = time.map(RobotSnoozeMotion.phaseTrack(letter: index).value(at:)) ?? RobotSnoozeMotion.restPhases[index]
            // On whole pixels, so a letter that stands still is sharp.
            let place = Self.point(on: ways[index], phase)
            letter.position = CGPoint(x: (place.x * scale).rounded() / scale, y: (place.y * scale).rounded() / scale)
            letter.opacity = Float(sin(.pi * phase))
        }
    }

    override func run(_ scene: RobotScene, side: CGFloat) {
        let look = scene.look
        if look.blinks {
            if look.eyes == .happy { blinkEyes.loop(RobotBlink.track, on: "opacity") }
            if look.eyes == .open { openEyes.loop(RobotBlink.track, on: "transform.scale.y") { 1 - (1 - RobotEyes.shutScale) * $0 } }
        }
        if look.antenna == .glowing { blueHalo.loop(RobotAntennaPulse.track, on: "opacity", RobotAntennaLight.blueStrength) }
        if look.antenna == .amber { amberHalo.loop(RobotAntennaPulse.track, on: "opacity", RobotAntennaLight.amberStrength) }
        for (index, wisp) in wisps.enumerated() where index < look.wisps {
            for (number, copy) in wisp.copies.enumerated() {
                copy.rise.loop(RobotSteamMotion.stretchTrack(wisp: index, copy: number), on: "transform.scale.y")
                copy.rise.loop(RobotSteamMotion.liftTrack(wisp: index, copy: number), on: "transform.translation.y") { -$0 * side }
                copy.rise.loop(RobotSteamMotion.strengthTrack(wisp: index, copy: number), on: "opacity")
                copy.lean.loop(RobotSteamMotion.swayTrack(wisp: index), on: "transform") { NSValue(caTransform3D: Self.lean($0, wisp: index)) }
            }
        }
        guard look.snoozes else { return }
        for (index, letter) in letters.enumerated() where index < ways.count {
            letter.loop(RobotSnoozeMotion.phaseTrack(letter: index), on: "position") { NSValue(point: Self.point(on: self.ways[index], $0)) }
            letter.loop(RobotSnoozeMotion.strengthTrack(letter: index), on: "opacity")
        }
    }

    override func blink(_ scene: RobotScene) {
        if scene.look.eyes == .happy { tap(blinkEyes, "opacity", open: 0, shut: 1) }
        if scene.look.eyes == .open { tap(openEyes, "transform.scale.y", open: 1, shut: RobotEyes.shutScale) }
    }

    /// The foot stays in the coffee, the top leans the most.
    private static func lean(_ sway: Double, wisp: Int) -> CATransform3D {
        var transform = CATransform3DIdentity
        transform.m21 = -sway * RobotSteamMotion.lean / RobotWisp.all[wisp].height
        return transform
    }

    private static func point(on way: (from: CGPoint, to: CGPoint), _ phase: Double) -> CGPoint {
        CGPoint(x: way.from.x + (way.to.x - way.from.x) * phase, y: way.from.y + (way.to.y - way.from.y) * phase)
    }
}
