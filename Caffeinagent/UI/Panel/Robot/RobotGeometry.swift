import CoreGraphics

// Written by scripts/build-robot-hero.py from assets/AppIcon-4096.png.
// Run the script again to change it.

/// Where the parts of the robot are in the pictures RobotTile and RobotBody,
/// from 0 to 1.
enum RobotGeometry {
    /// One eye of the icon: an arc with round ends.
    struct Eye {
        var centerX: CGFloat
        /// Of the line through the middle of the arc.
        var top: CGFloat
        /// How far the ends lie below the top.
        var sagitta: CGFloat
        var halfChord: CGFloat
        var width: CGFloat
    }

    /// One row of a wisp of steam.
    struct WispRow {
        var y: CGFloat
        var left: CGFloat
        var right: CGFloat
        /// How much the steam covers, 0 to 1.
        var strength: CGFloat
    }

    static let leftEye = RobotGeometry.Eye(centerX: 0.38528, top: 0.42512, sagitta: 0.03475, halfChord: 0.04678, width: 0.03287)
    static let rightEye = RobotGeometry.Eye(centerX: 0.61426, top: 0.425, sagitta: 0.0353, halfChord: 0.04685, width: 0.03274)
    static let eyeColor: (red: Double, green: Double, blue: Double) = (0.7102, 0.8833, 0.9789)
    static let visor = CGRect(x: 0.26, y: 0.312, width: 0.47933, height: 0.26067)
    static let antennaCenter = CGPoint(x: 0.50011, y: 0.146)
    static let antennaRadius: CGFloat = 0.04467
    /// Where the steam leaves the coffee.
    static let cupRim = CGPoint(x: 0.51855, y: 0.68333)
    /// The picture in points. The menu shows it larger or smaller.
    static let points: CGFloat = 100
    /// The picture is this much larger than the rounded square it shows in.
    static let shownScale: CGFloat = 100 / 96
    /// The corner radius of that square, as a share of its side.
    static let corner: CGFloat = 0.225

    static let largeWisp: [WispRow] = [
        .init(y: 0.49833, left: 0.49128, right: 0.49283, strength: 0.133),
        .init(y: 0.505, left: 0.48404, right: 0.49273, strength: 0.217),
        .init(y: 0.51233, left: 0.47874, right: 0.49492, strength: 0.287),
        .init(y: 0.519, left: 0.47672, right: 0.4999, strength: 0.331),
        .init(y: 0.52567, left: 0.47715, right: 0.50968, strength: 0.342),
        .init(y: 0.53233, left: 0.47844, right: 0.5173, strength: 0.357),
        .init(y: 0.53967, left: 0.48216, right: 0.52653, strength: 0.36),
        .init(y: 0.54633, left: 0.48628, right: 0.5348, strength: 0.337),
        .init(y: 0.553, left: 0.49266, right: 0.54195, strength: 0.325),
        .init(y: 0.56033, left: 0.49882, right: 0.54826, strength: 0.346),
        .init(y: 0.567, left: 0.50307, right: 0.55214, strength: 0.382),
        .init(y: 0.57367, left: 0.50727, right: 0.55464, strength: 0.295),
        .init(y: 0.581, left: 0.5089, right: 0.55589, strength: 0.359),
        .init(y: 0.58767, left: 0.50689, right: 0.55525, strength: 0.394),
        .init(y: 0.59433, left: 0.50443, right: 0.5548, strength: 0.386),
        .init(y: 0.601, left: 0.50305, right: 0.55117, strength: 0.389),
        .init(y: 0.60833, left: 0.50201, right: 0.54688, strength: 0.394),
        .init(y: 0.615, left: 0.49988, right: 0.54187, strength: 0.397),
        .init(y: 0.62167, left: 0.49805, right: 0.53584, strength: 0.409),
        .init(y: 0.629, left: 0.4943, right: 0.52984, strength: 0.404),
        .init(y: 0.63567, left: 0.49392, right: 0.52506, strength: 0.314),
        .init(y: 0.64233, left: 0.49262, right: 0.52129, strength: 0.309),
        .init(y: 0.64967, left: 0.49394, right: 0.51846, strength: 0.336),
        .init(y: 0.65633, left: 0.49571, right: 0.51677, strength: 0.367),
        .init(y: 0.663, left: 0.49776, right: 0.51615, strength: 0.364),
        .init(y: 0.66967, left: 0.50085, right: 0.51634, strength: 0.291),
        .init(y: 0.677, left: 0.50719, right: 0.51827, strength: 0.228),
        .init(y: 0.68367, left: 0.5179, right: 0.51986, strength: 0.144),
    ]

    static let smallWisp: [WispRow] = [
        .init(y: 0.55967, left: 0.47014, right: 0.47157, strength: 0.131),
        .init(y: 0.56367, left: 0.46746, right: 0.4728, strength: 0.161),
        .init(y: 0.567, left: 0.4648, right: 0.47402, strength: 0.193),
        .init(y: 0.571, left: 0.4616, right: 0.47549, strength: 0.233),
        .init(y: 0.57433, left: 0.45893, right: 0.47671, strength: 0.266),
        .init(y: 0.57833, left: 0.4558, right: 0.47805, strength: 0.302),
        .init(y: 0.58167, left: 0.45319, right: 0.4779, strength: 0.322),
        .init(y: 0.58567, left: 0.44884, right: 0.47616, strength: 0.336),
        .init(y: 0.589, left: 0.44521, right: 0.4745, strength: 0.345),
        .init(y: 0.593, left: 0.4413, right: 0.47244, strength: 0.353),
        .init(y: 0.59633, left: 0.43869, right: 0.47086, strength: 0.355),
        .init(y: 0.60033, left: 0.43621, right: 0.46747, strength: 0.347),
        .init(y: 0.60367, left: 0.43452, right: 0.46506, strength: 0.341),
        .init(y: 0.60767, left: 0.43277, right: 0.46264, strength: 0.339),
        .init(y: 0.611, left: 0.43155, right: 0.46115, strength: 0.34),
        .init(y: 0.615, left: 0.43085, right: 0.45962, strength: 0.338),
        .init(y: 0.61833, left: 0.43067, right: 0.45875, strength: 0.341),
        .init(y: 0.62233, left: 0.43067, right: 0.45805, strength: 0.345),
        .init(y: 0.62567, left: 0.43072, right: 0.45801, strength: 0.344),
        .init(y: 0.62967, left: 0.43164, right: 0.45845, strength: 0.337),
        .init(y: 0.633, left: 0.43429, right: 0.4591, strength: 0.321),
        .init(y: 0.637, left: 0.43862, right: 0.45975, strength: 0.291),
        .init(y: 0.64033, left: 0.44226, right: 0.46029, strength: 0.265),
        .init(y: 0.64433, left: 0.44664, right: 0.46095, strength: 0.234),
        .init(y: 0.64767, left: 0.45028, right: 0.46149, strength: 0.208),
        .init(y: 0.65167, left: 0.45465, right: 0.46214, strength: 0.177),
        .init(y: 0.655, left: 0.45829, right: 0.46268, strength: 0.152),
        .init(y: 0.659, left: 0.46195, right: 0.46323, strength: 0.128),
    ]
}
