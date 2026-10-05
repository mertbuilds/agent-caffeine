#!/usr/bin/env python3
"""Builds the robot of the menu from the icon master.

Run from the repo root:

    uv run --with pillow --with numpy --with scipy python scripts/build-robot-hero.py

The menu shows the robot of the app icon and moves its eyes and its steam.
So the picture in the menu is the master (assets/AppIcon-4096.png) without
the eyes and without the steam, and the app draws both on top. This script
writes:

- Caffeinagent/Assets.xcassets/RobotBase.imageset: a square of the tile round
  the robot, at 1x and 2x (a Mac has no 3x). The inside of the visor is filled with its
  own gradient, the steam with what lies to its left and right.
- Caffeinagent/Assets.xcassets/RobotEyes.imageset: the inside of the visor
  as the icon has it, with the eyes and their glow, of the same size and
  clear everywhere else.
- Caffeinagent/UI/Panel/Robot/RobotGeometry.swift: where the eyes, the
  visor, the cup and the antenna are in that picture, from 0 to 1, and the
  outline of each wisp of steam.

Pass --debug DIR to also write the steps as pictures.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage, optimize, sparse
from scipy.sparse.linalg import spsolve
from scipy.spatial import cKDTree

ROOT = Path(__file__).resolve().parent.parent
MASTER = ROOT / "assets/AppIcon-4096.png"
CATALOG = ROOT / "Caffeinagent/Assets.xcassets"
GEOMETRY = ROOT / "Caffeinagent/UI/Panel/Robot/RobotGeometry.swift"

# All work happens on the master at half size. The largest export is a
# seventh of that, so nothing finer survives.
WORK = 2048
# Side of the exported square in work pixels, and its size in points.
CROP = 1500
POINTS = 100
# The picture is this much larger than the rounded square the menu shows it
# behind, so it can move up and down without an empty edge. The square is
# 96 points in the menu, so the picture is drawn pixel for pixel.
SHOWN_SCALE = 100 / 96
BOB_ROOM = 0.02
# The corner radius of that square, as a share of its side.
CORNER = 0.225
# The visor ends at this row where the steam crosses it, and is lighter
# this far to the left and right of the steam.
VISOR_FOOT = 1092
HAZE = 45
# The rim of the visor that stays as it is.
VISOR_RIM = 20
# Where the steam is, with room on both sides.
STEAM_BOX = (860, 1190, 950, 1290)
# For each wisp, all in the box of the steam: a row inside it and a column
# of it there, to start from. The first and last row where its edges can be
# read: the small wisp fades on the rim of the cup, so its edges are drawn
# straight from there to its tip. Its upper and its lower tip, as column
# and row.
WISPS = {
    "large": {"seed": (60, 145), "rows": (32, 302), "top": (152, 29), "foot": (193, 307)},
    "small": {"seed": (152, 112), "rows": (147, 227), "top": (120, 121), "foot": (108, 270)},
}
WISP_SAMPLES = 28

parser = argparse.ArgumentParser()
parser.add_argument("--debug", type=Path)
args = parser.parse_args()

master = Image.open(MASTER).convert("RGBA").resize((WORK, WORK), Image.LANCZOS)
pixels = np.asarray(master).astype(np.float32)
rgb, alpha = pixels[..., :3].copy(), pixels[..., 3]
original = rgb.copy()


def largest(mask):
    labels, count = ndimage.label(mask)
    sizes = ndimage.sum(mask, labels, range(1, count + 1))
    return labels == 1 + int(np.argmax(sizes))


# MARK: Steam

x0, x1, y0, y1 = STEAM_BOX
columns = np.arange(x1 - x0)
luma = rgb[y0:y1, x0:x1].mean(axis=2)
# Steam only makes a pixel lighter. A cubic through each row that ignores
# what lies above it gives the row without steam.
excess = np.zeros_like(luma)
for row in range(luma.shape[0]):
    weights = np.ones_like(columns, dtype=np.float32)
    for _ in range(12):
        base = np.polyval(np.polyfit(columns, luma[row], 3, w=weights), columns)
        weights = np.where(luma[row] - base > 1.5, 0.02, 1.0)
    excess[row] = np.clip((luma[row] - base) / np.maximum(255 - base, 25), 0, 1)
excess = ndimage.gaussian_filter(excess, 1.0)


def runs(row):
    found, start = [], None
    for x, lit in enumerate(np.append(excess[row] > 0.07, False)):
        if lit and start is None:
            start = x
        if not lit and start is not None:
            if x - start >= 4:
                found.append((start, x - 1))
            start = None
    return found


def trace(seed, rows, top, foot):
    """The left and right edge of one wisp, row by row."""
    seed_row, seed_x = seed
    edges = {}
    for step in (1, -1):
        last, missed, row = None, 0, seed_row
        while rows[0] <= row <= rows[1]:
            if last is None:
                candidates = [r for r in runs(row) if r[0] <= seed_x <= r[1]]
            else:
                candidates = [r for r in runs(row) if r[0] <= last[1] and r[1] >= last[0]]
            # Where the wisp crosses an edge of the robot the row gives a
            # wrong run, far wider or shifted. Those rows are left out and
            # filled in from the rows round them.
            reach = min(4 + missed, 12)
            good = [r for r in candidates if last is None or (abs(r[0] - last[0]) <= reach and abs(r[1] - last[1]) <= reach)]
            if good:
                last, missed = good[0], 0
                edges[row] = (*last, float(excess[row, last[0]:last[1] + 1].mean()))
            else:
                missed += 1
            row += step
    for x, row in (top, foot):
        edges[row] = (x, x, 0.12)
    found = np.array(sorted(edges))
    left, right, strength = (np.array([edges[r][i] for r in found], dtype=np.float32) for i in range(3))
    every = np.arange(found.min(), found.max() + 1)
    smooth = lambda values, sigma: ndimage.gaussian_filter1d(np.interp(every, found, values), sigma, mode="nearest")
    return every, smooth(left, 2.5), smooth(right, 2.5), smooth(strength, 4)


wisps = {name: trace(**wisp) for name, wisp in WISPS.items()}

steam = np.zeros(luma.shape, dtype=bool)
for every, left, right, _ in wisps.values():
    for row, a, b in zip(every, left, right):
        steam[row, max(int(a), 0):int(np.ceil(b)) + 1] = True
    # The tips are thinner than a run can be.
    for row in list(range(every.min() - 14, every.min())) + list(range(every.max() + 1, every.max() + 15)):
        end = 0 if row < every.min() else -1
        if 0 <= row < steam.shape[0]:
            steam[row, int(left[end]) - 2:int(right[end]) + 3] = True
steam = ndimage.binary_dilation(steam, iterations=10)

# Round the steam the visor is a little lighter. That part goes too.
over_visor = slice(0, VISOR_FOOT - y0)
steam[over_visor] = ndimage.binary_dilation(steam[over_visor], structure=np.ones((1, 2 * HAZE + 1), dtype=bool))

# Each row of steam becomes the blend of the pixels to its left and right.
# What the steam crosses runs from left to right, so this keeps every edge.
# An edge that slopes, like the rim of the cup, lies a few rows lower on one
# side: `drop` is that many rows, and the blend follows the slope.
source = rgb[y0:y1, x0:x1].copy()
box = rgb[y0:y1, x0:x1]
height = source.shape[0]
reach = 14


def column(x, row, shift):
    rows = np.clip(np.arange(row - reach, row + reach + 1) + shift, 0, height - 1)
    return source[rows, x - 3:x + 4].mean(axis=1)


for row in range(height):
    lit = np.where(steam[row])[0]
    if lit.size == 0:
        continue
    for segment in np.split(lit, np.where(np.diff(lit) > 1)[0] + 1):
        a, b = segment[0] - 4, segment[-1] + 4
        drops = np.arange(-10, 11)
        misses = [np.abs(column(a, row, 0) - column(b, row, drop)).mean() + 0.15 * abs(drop) for drop in drops]
        drop = drops[int(np.argmin(misses))]
        share = (segment - a) / (b - a)
        before_rows = np.clip(row - share * drop, 0, height - 1)
        after_rows = np.clip(row + (1 - share) * drop, 0, height - 1)
        for channel in range(3):
            before = np.interp(before_rows, np.arange(height), source[:, a - 3:a + 1, channel].mean(axis=1))
            after = np.interp(after_rows, np.arange(height), source[:, b:b + 4, channel].mean(axis=1))
            box[row, segment, channel] = before * (1 - share) + after * share
cleaned = ndimage.gaussian_filter(box, (1.2, 1.2, 0))
feather = ndimage.gaussian_filter(steam.astype(np.float32), 1.5)[..., None]
rgb[y0:y1, x0:x1] = box * (1 - feather) + cleaned * feather

# MARK: Eyes

red, green, blue = original[..., 0], original[..., 1], original[..., 2]
visor = largest((red < 70) & (green < 80) & (blue < 150) & (alpha > 250))
visor = ndimage.binary_fill_holes(ndimage.binary_closing(visor, iterations=3))
visor_rows, visor_columns = np.where(visor)
visor_box = (visor_columns.min(), visor_rows.min(), visor_columns.max() + 1, visor_rows.max() + 1)

cores = visor & (red > 150)
labels, count = ndimage.label(cores)
sizes = ndimage.sum(cores, labels, range(1, count + 1))
eyes = [labels == 1 + i for i in np.argsort(sizes)[::-1][:2]]
eyes.sort(key=lambda mask: np.where(mask)[1].mean())


def arc_points(center_x, top, sagitta, half_chord):
    """An arc through the two ends and the top, as points."""
    radius = (half_chord ** 2 + sagitta ** 2) / (2 * sagitta)
    span = np.arcsin(min(half_chord / radius, 1))
    angles = np.linspace(-span, span, 240)
    return np.stack([center_x + radius * np.sin(angles), top + radius - radius * np.cos(angles)], axis=1)


def fit_eye(mask):
    rows, cols = np.where(mask)
    pad = 12
    grid_y, grid_x = np.mgrid[rows.min() - pad:rows.max() + pad, cols.min() - pad:cols.max() + pad]
    target = mask[grid_y, grid_x]
    points = np.stack([grid_x.ravel(), grid_y.ravel()], axis=1).astype(np.float64)

    def miss(values):
        center_x, top, sagitta, half_chord, width = values
        if sagitta < 5 or half_chord < 5 or width < 5:
            return 1.0
        distance, _ = cKDTree(arc_points(center_x, top, sagitta, half_chord)).query(points)
        # A soft edge, so the fit can move by less than a pixel.
        drawn = np.clip(width / 2 - distance + 0.5, 0, 1).reshape(target.shape)
        return 1 - np.minimum(drawn, target).sum() / np.maximum(drawn, target).sum()

    start = [cols.mean(), rows.min() + 26, 50, 67, 52]
    result = optimize.minimize(miss, start, method="Nelder-Mead", options={"xatol": 0.05, "fatol": 1e-5, "maxiter": 2000})
    return result.x, 1 - result.fun


fits = [fit_eye(mask) for mask in eyes]
eye_color = np.mean([original[mask].mean(axis=0) for mask in eyes], axis=0)


def poisson_fill(image, hole, ring):
    """Fills `hole` with the plane-and-curve of `ring`, joined to the
    pixels round the hole without a step."""
    rows, cols = np.where(ring)
    terms = lambda r, c: np.stack([np.ones_like(r), r, c, r * r, r * c, c * c], axis=1).astype(np.float64)
    scale = float(WORK)
    fit, *_ = np.linalg.lstsq(terms(rows / scale, cols / scale), image[rows, cols], rcond=None)
    all_rows, all_cols = np.mgrid[0:image.shape[0], 0:image.shape[1]]
    trend = (terms(all_rows.ravel() / scale, all_cols.ravel() / scale) @ fit).reshape(image.shape)
    rest = image - trend

    index = -np.ones(hole.shape, dtype=np.int64)
    hole_rows, hole_cols = np.where(hole)
    count = hole_rows.size
    index[hole_rows, hole_cols] = np.arange(count)
    known = np.zeros((count, image.shape[2]))
    entries = [(np.arange(count), np.arange(count), np.full(count, 4.0))]
    for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        other = index[hole_rows + dr, hole_cols + dc]
        free = other >= 0
        entries.append((np.where(free)[0], other[free], np.full(free.sum(), -1.0)))
        known[~free] += rest[hole_rows[~free] + dr, hole_cols[~free] + dc]
    rows, cols, values = (np.concatenate(part) for part in zip(*entries))
    matrix = sparse.csr_matrix((values, (rows, cols)), shape=(count, count))
    solved = np.stack([spsolve(matrix, known[:, channel]) for channel in range(image.shape[2])], axis=1)
    filled = image.copy()
    filled[hole_rows, hole_cols] = solved + trend[hole_rows, hole_cols]
    return filled


# The eyes light the whole visor a little, so all of its inside is filled
# anew from its rim: a smooth dark glass.
steam_free = rgb.copy()
hole = ndimage.binary_erosion(visor, iterations=VISOR_RIM)
ring = ndimage.binary_dilation(hole, iterations=10) & ~hole
rows, cols = np.where(visor)
window = (slice(rows.min(), rows.max() + 1), slice(cols.min(), cols.max() + 1))
rgb[window] = poisson_fill(rgb[window], hole[window], ring[window])

# The eyes of the icon with their glow, as a layer of their own: over the
# picture it gives the icon back, pixel for pixel.
eyes_alpha = ndimage.gaussian_filter(ndimage.binary_erosion(hole, iterations=8).astype(np.float32), 3)

# MARK: Antenna

ball_zone = np.zeros(visor.shape, dtype=bool)
ball_zone[: visor_box[1] - 60, WORK // 2 - 200:WORK // 2 + 200] = True
light = largest(ball_zone & (red > 150) & (alpha > 250))
light_rows, light_cols = np.where(light)
widths = np.array([np.count_nonzero(light[row]) for row in range(light_rows.min(), light_rows.max() + 1)])
# The ball ends where the light part narrows to the stem.
stem = np.argmax(widths[10:] < 0.6 * np.maximum.accumulate(widths)[10:]) + 10
ball_radius = widths[:stem].max() / 2
ball_top = light_rows.min()
ball_x = light_cols[light_rows < ball_top + ball_radius].mean() + 0.5
ball_y = ball_top + ball_radius

# MARK: Crop

# The robot from the top of the antenna to the foot of the cup.
middle = WORK // 2
column = (np.abs(rgb[:, middle - 20:middle + 20].mean(axis=1) - np.array([235, 226, 212])).max(axis=1) < 60)
foot = np.where(column)[0].max()
center_y = (ball_top + foot) / 2
left = round(ball_x - CROP / 2)
top = round(center_y - CROP / 2)
# The menu shows the middle of the picture behind a rounded square, and the
# picture moves a little behind it. What can show must lie on the tile.
shown = CROP / SHOWN_SCALE
grid_y, grid_x = np.mgrid[0:CROP, 0:CROP] + 0.5 - CROP / 2
reach = shown / 2 + BOB_ROOM * shown
inner = reach - CORNER * shown
corner_x, corner_y = np.maximum(np.abs(grid_x) - inner, 0), np.maximum(np.abs(grid_y) - inner, 0)
visible = (np.abs(grid_x) <= reach) & (np.abs(grid_y) <= reach) & (np.hypot(corner_x, corner_y) <= CORNER * shown)
assert alpha[top:top + CROP, left:left + CROP][visible].min() > 250, "the crop leaves the tile"


def unit(x=None, y=None, length=None):
    if length is not None:
        return round(float(length) / CROP, 5)
    return round(float(x - left) / CROP, 5) if x is not None else round(float(y - top) / CROP, 5)


geometry = {
    "eyes": [
        {
            "centerX": unit(x=fit[0] + 0.5),
            "top": unit(y=fit[1] + 0.5),
            "sagitta": unit(length=fit[2]),
            "halfChord": unit(length=fit[3]),
            "width": unit(length=fit[4]),
            "overlap": round(float(score), 4),
        }
        for fit, score in fits
    ],
    "eyeColor": [round(float(v) / 255, 4) for v in eye_color],
    "visor": [unit(x=visor_box[0]), unit(y=visor_box[1]), unit(length=visor_box[2] - visor_box[0]), unit(length=visor_box[3] - visor_box[1])],
    "antenna": {"centerX": unit(x=ball_x), "centerY": unit(y=ball_y), "radius": unit(length=ball_radius)},
    "wisps": {},
}

for name, (every, edge_left, edge_right, strength) in wisps.items():
    picks = np.linspace(0, every.size - 1, WISP_SAMPLES).round().astype(int)
    geometry["wisps"][name] = [
        [unit(y=y0 + every[i] + 0.5), unit(x=x0 + edge_left[i]), unit(x=x0 + edge_right[i] + 1), round(float(strength[i]), 3)]
        for i in picks
    ]
large = wisps["large"]
geometry["cupRim"] = {
    "centerX": unit(x=x0 + (large[1][-1] + large[2][-1]) / 2),
    "centerY": unit(y=y0 + large[0].max()),
}

# MARK: Output

def cut(image):
    return np.clip(image[top:top + CROP, left:left + CROP], 0, 255).round().astype(np.uint8)


crop = Image.fromarray(cut(rgb))
eyes_crop = Image.fromarray(np.dstack([cut(steam_free), cut(eyes_alpha * 255)]), "RGBA")
contents = lambda value: json.dumps(value, indent=2) + "\n"
CATALOG.mkdir(parents=True, exist_ok=True)
(CATALOG / "Contents.json").write_text(contents({"info": {"author": "xcode", "version": 1}}))
for set_name, file_name, picture in (("RobotBase", "robot-base", crop), ("RobotEyes", "robot-eyes", eyes_crop)):
    folder = CATALOG / f"{set_name}.imageset"
    folder.mkdir(exist_ok=True)
    images = []
    for scale in (1, 2):
        name = f"{file_name}@{scale}x.png" if scale > 1 else f"{file_name}.png"
        # Premultiplied while it shrinks, so no dark fringe forms where the
        # layer fades out.
        small = picture.convert("RGBa").resize((POINTS * scale, POINTS * scale), Image.LANCZOS).convert("RGBA") if picture.mode == "RGBA" else picture.resize((POINTS * scale, POINTS * scale), Image.LANCZOS)
        small.save(folder / name, optimize=True)
        images.append({"idiom": "universal", "filename": name, "scale": f"{scale}x"})
        print(f"{name}: {(folder / name).stat().st_size / 1024:.1f} KB")
    (folder / "Contents.json").write_text(contents({"images": images, "info": {"author": "xcode", "version": 1}}))


def swift_eye(eye):
    return (
        f"RobotGeometry.Eye(centerX: {eye['centerX']}, top: {eye['top']}, sagitta: {eye['sagitta']}, "
        f"halfChord: {eye['halfChord']}, width: {eye['width']})"
    )


def swift_wisp(samples):
    lines = ",\n".join(f"        .init(y: {y}, left: {a}, right: {b}, strength: {s})" for y, a, b, s in samples)
    return f"[\n{lines},\n    ]"


v, ant, rim = geometry["visor"], geometry["antenna"], geometry["cupRim"]
GEOMETRY.write_text(f"""import CoreGraphics

// Written by scripts/build-robot-hero.py from assets/AppIcon-4096.png.
// Run the script again to change it.

/// Where the parts of the robot are in the picture RobotBase, from 0 to 1.
enum RobotGeometry {{
    /// One eye of the icon: an arc with round ends.
    struct Eye {{
        var centerX: CGFloat
        /// Of the line through the middle of the arc.
        var top: CGFloat
        /// How far the ends lie below the top.
        var sagitta: CGFloat
        var halfChord: CGFloat
        var width: CGFloat
    }}

    /// One row of a wisp of steam.
    struct WispRow {{
        var y: CGFloat
        var left: CGFloat
        var right: CGFloat
        /// How much the steam covers, 0 to 1.
        var strength: CGFloat
    }}

    static let leftEye = {swift_eye(geometry['eyes'][0])}
    static let rightEye = {swift_eye(geometry['eyes'][1])}
    static let eyeColor: (red: Double, green: Double, blue: Double) = ({geometry['eyeColor'][0]}, {geometry['eyeColor'][1]}, {geometry['eyeColor'][2]})
    static let visor = CGRect(x: {v[0]}, y: {v[1]}, width: {v[2]}, height: {v[3]})
    static let antennaCenter = CGPoint(x: {ant['centerX']}, y: {ant['centerY']})
    static let antennaRadius: CGFloat = {ant['radius']}
    /// Where the steam leaves the coffee.
    static let cupRim = CGPoint(x: {rim['centerX']}, y: {rim['centerY']})
    /// The picture in points. The menu shows it larger or smaller.
    static let points: CGFloat = {POINTS}
    /// The picture is this much larger than the rounded square it shows in.
    static let shownScale: CGFloat = {POINTS} / 96
    /// The corner radius of that square, as a share of its side.
    static let corner: CGFloat = {CORNER}

    static let largeWisp: [WispRow] = {swift_wisp(geometry['wisps']['large'])}

    static let smallWisp: [WispRow] = {swift_wisp(geometry['wisps']['small'])}
}}
""")

print(json.dumps({k: v for k, v in geometry.items() if k != "wisps"}, indent=2))
print("crop in the 4096 master:", [left * 2, top * 2, CROP * 2])

if args.debug:
    args.debug.mkdir(parents=True, exist_ok=True)
    crop.save(args.debug / "base.png")
    eyes_crop.save(args.debug / "eyes.png")
    both = crop.convert("RGBA")
    both.alpha_composite(eyes_crop)
    both.save(args.debug / "base-with-eyes.png")
    Image.fromarray(original[top:top + CROP, left:left + CROP].round().astype(np.uint8)).save(args.debug / "original.png")
    Image.fromarray((steam * 255).astype(np.uint8)).save(args.debug / "steam-mask.png")
    traced = original[y0:y1, x0:x1].copy()
    for every, edge_left, edge_right, _ in wisps.values():
        for row, a, b in zip(every, edge_left, edge_right):
            traced[row, int(a)] = (255, 0, 0)
            traced[row, int(b)] = (0, 255, 0)
    traced = Image.fromarray(traced.round().astype(np.uint8))
    traced.resize((traced.width * 3, traced.height * 3), Image.NEAREST).save(args.debug / "steam-traced.png")
    for name, (zx0, zy0, zx1, zy1) in {"visor": (640, 680, 1410, 1110), "steam": (860, 950, 1190, 1290)}.items():
        zoom = Image.fromarray(np.clip(rgb[zy0:zy1, zx0:zx1], 0, 255).round().astype(np.uint8))
        zoom.resize((zoom.width * 2, zoom.height * 2), Image.LANCZOS).save(args.debug / f"zoom-{name}.png")
