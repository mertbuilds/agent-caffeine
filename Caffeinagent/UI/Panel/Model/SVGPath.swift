import CoreGraphics
import Foundation

/// Reads SVG path data into a `CGPath`. All commands of the path grammar,
/// also arc flags that are written without a separator.
enum SVGPath {
    static func cgPath(_ data: String) -> CGPath {
        var reader = Reader(bytes: Array(data.utf8))
        let path = CGMutablePath()
        var current = CGPoint.zero
        var start = CGPoint.zero
        /// The second control point of the last curve, for S and T.
        var lastControl: CGPoint?
        var lastCommand: UInt8 = 0
        var command: UInt8 = 0

        while true {
            if let next = reader.command() {
                command = next
            } else if command == 0 || reader.isAtEnd || !reader.startsNumber {
                break
            } else if command == UInt8(ascii: "M") {
                // More pairs after a move are lines.
                command = UInt8(ascii: "L")
            } else if command == UInt8(ascii: "m") {
                command = UInt8(ascii: "l")
            }
            let relative = command >= UInt8(ascii: "a")
            func point() -> CGPoint? {
                guard let x = reader.number(), let y = reader.number() else { return nil }
                return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            var control: CGPoint?
            switch UnicodeScalar(command).properties.uppercaseMapping {
            case "M":
                guard let to = point() else { return path }
                path.move(to: to)
                current = to
                start = to
            case "L":
                guard let to = point() else { return path }
                path.addLine(to: to)
                current = to
            case "H":
                guard let x = reader.number() else { return path }
                current.x = relative ? current.x + x : x
                path.addLine(to: current)
            case "V":
                guard let y = reader.number() else { return path }
                current.y = relative ? current.y + y : y
                path.addLine(to: current)
            case "C":
                guard let c1 = point(), let c2 = point(), let to = point() else { return path }
                path.addCurve(to: to, control1: c1, control2: c2)
                control = c2
                current = to
            case "S":
                guard let c2 = point(), let to = point() else { return path }
                let smooth = "CcSs".utf8.contains(lastCommand)
                path.addCurve(to: to, control1: reflected(smooth ? lastControl : nil, about: current), control2: c2)
                control = c2
                current = to
            case "Q":
                guard let c = point(), let to = point() else { return path }
                path.addQuadCurve(to: to, control: c)
                control = c
                current = to
            case "T":
                guard let to = point() else { return path }
                let smooth = "QqTt".utf8.contains(lastCommand)
                let c = reflected(smooth ? lastControl : nil, about: current)
                path.addQuadCurve(to: to, control: c)
                control = c
                current = to
            case "A":
                guard let rx = reader.number(), let ry = reader.number(), let rotation = reader.number(),
                      let large = reader.flag(), let sweep = reader.flag(), let to = point() else { return path }
                addArc(to: path, from: current, to: to, rx: rx, ry: ry, rotation: rotation * .pi / 180, large: large, sweep: sweep)
                current = to
            case "Z":
                path.closeSubpath()
                current = start
            default:
                return path
            }
            lastControl = control
            lastCommand = command
            if command == UInt8(ascii: "Z") || command == UInt8(ascii: "z") { command = 0 }
        }
        return path
    }

    private static func reflected(_ control: CGPoint?, about point: CGPoint) -> CGPoint {
        guard let control else { return point }
        return CGPoint(x: 2 * point.x - control.x, y: 2 * point.y - control.y)
    }

    /// From the end points to the centre, as the SVG implementation notes
    /// give it (F.6.5), then drawn as an arc of the unit circle.
    private static func addArc(to path: CGMutablePath, from: CGPoint, to: CGPoint, rx: CGFloat, ry: CGFloat, rotation: CGFloat, large: Bool, sweep: Bool) {
        var rx = abs(rx), ry = abs(ry)
        guard rx > 0, ry > 0, from != to else {
            path.addLine(to: to)
            return
        }
        let (cosR, sinR) = (cos(rotation), sin(rotation))
        let dx = (from.x - to.x) / 2, dy = (from.y - to.y) / 2
        let x1 = cosR * dx + sinR * dy
        let y1 = -sinR * dx + cosR * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = denominator == 0 ? 0 : max(0, numerator / denominator).squareRoot()
        if large == sweep { factor = -factor }
        let cx1 = factor * rx * y1 / ry
        let cy1 = -factor * ry * x1 / rx
        let center = CGPoint(
            x: cosR * cx1 - sinR * cy1 + (from.x + to.x) / 2,
            y: sinR * cx1 + cosR * cy1 + (from.y + to.y) / 2
        )
        let startAngle = atan2((y1 - cy1) / ry, (x1 - cx1) / rx)
        let endAngle = atan2((-y1 - cy1) / ry, (-x1 - cx1) / rx)
        var delta = endAngle - startAngle
        if sweep, delta < 0 { delta += 2 * .pi }
        if !sweep, delta > 0 { delta -= 2 * .pi }
        let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: rotation).scaledBy(x: rx, y: ry)
        path.addArc(center: .zero, radius: 1, startAngle: startAngle, endAngle: startAngle + delta, clockwise: delta < 0, transform: transform)
    }

    private struct Reader {
        let bytes: [UInt8]
        var index = 0

        var isAtEnd: Bool {
            mutating get {
                skipSeparators()
                return index >= bytes.count
            }
        }

        var startsNumber: Bool {
            mutating get {
                skipSeparators()
                guard index < bytes.count else { return false }
                let byte = bytes[index]
                return isDigit(byte) || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "+") || byte == UInt8(ascii: ".")
            }
        }

        mutating func command() -> UInt8? {
            skipSeparators()
            guard index < bytes.count else { return nil }
            let byte = bytes[index]
            guard (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z")) || (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) else { return nil }
            index += 1
            return byte
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            let begin = index
            if index < bytes.count, bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+") { index += 1 }
            skipDigits()
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                index += 1
                skipDigits()
            }
            if index + 1 < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
                let next = bytes[index + 1]
                if isDigit(next) || next == UInt8(ascii: "-") || next == UInt8(ascii: "+") {
                    index += 2
                    skipDigits()
                }
            }
            guard index > begin, let value = Double(String(decoding: bytes[begin..<index], as: UTF8.self)) else {
                index = begin
                return nil
            }
            return CGFloat(value)
        }

        /// One character, so "01" reads as two flags.
        mutating func flag() -> Bool? {
            skipSeparators()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "0") || bytes[index] == UInt8(ascii: "1") else { return nil }
            defer { index += 1 }
            return bytes[index] == UInt8(ascii: "1")
        }

        private func isDigit(_ byte: UInt8) -> Bool {
            byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
        }

        private mutating func skipDigits() {
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }

        private mutating func skipSeparators() {
            while index < bytes.count, [UInt8(ascii: " "), UInt8(ascii: ","), 9, 10, 13].contains(bytes[index]) { index += 1 }
        }
    }
}
