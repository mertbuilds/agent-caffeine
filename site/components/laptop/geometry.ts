// A 14 inch MacBook Pro: 312.6 mm wide, 221.2 mm deep and 15.5 mm thick, of
// which the lid is about 4.5 mm. Sizes are hundredths of the scene's width,
// at 66 for the width; the scene is 100 by 70. The display is 302.5 by
// 196.5 mm inside a 5 mm bezel.
export const WIDTH = 66;
export const DEPTH = 46.7;
const BASE = 2.3;
const LID = 0.95;
export const BEZEL = 1.07;
export const CHIN = 4.15;
// The lid opens to 105 degrees and stands LIFT above the deck. The camera
// sits PERSPECTIVE away, level with ORIGIN; the laptop stands BACK behind its
// focus at ANCHOR and turns towards it by CAMERA degrees. The scene's CSS
// (laptop-scene.tsx and the screen in laptop.tsx) uses the same numbers.
export const OPEN = -75;
export const CAMERA = -15;
export const BACK = 14;
export const LIFT = 0.15;
const PERSPECTIVE = 200;
const ORIGIN = 0.22 * 70;
const ANCHOR = 0.78 * 70;
// The corners of both slabs, the lid's corners at the hinge, the aluminium
// rim round the display glass, and the hinge barrel under the display.
export const ROUND = 2.1;
const HINGE_ROUND = 0.4;
const RIM = 0.25;
const HINGE = 0.8;
const HINGE_SPAN = 26.4;

type Flat = readonly [number, number];
type Solid = readonly [number, number, number];

/**
 * A computed number cut to 4 decimals, and -0 to 0, so markup reads the same
 * from the server's HTML as from the client.
 */
export const fixed = (value: number) => Math.round(value * 1e4) / 1e4 || 0;
const cut = (value: number) => Math.round(value * 100) / 100 || 0;

const RADIAN = Math.PI / 180;
const [CAMERA_COS, CAMERA_SIN] = [Math.cos(CAMERA * RADIAN), Math.sin(CAMERA * RADIAN)];

/**
 * A point of the laptop, x across from its middle, y from the middle of the
 * deck towards the front and z up from the deck, where the CSS transforms put
 * it in the scene: x right, y down, z towards the eye.
 */
function scene([x, y, z]: Solid): Solid {
  return [50 + x, ANCHOR - z * CAMERA_COS - y * CAMERA_SIN, -z * CAMERA_SIN + y * CAMERA_COS - BACK];
}

function project(point: Solid): Flat {
  const [x, y, z] = scene(point);
  const scale = PERSPECTIVE / (PERSPECTIVE - z);
  return [50 + (x - 50) * scale, ORIGIN + (y - ORIGIN) * scale];
}

/** Whether a face through `point`, turned out along `normal`, faces the eye. */
function facesEye(point: Solid, [nx, ny, nz]: Solid): boolean {
  const [x, y, z] = scene(point);
  const [, sy, sz] = scene([nx, ny, nz]);
  const [, oy, oz] = scene([0, 0, 0]);
  return nx * (50 - x) + (sy - oy) * (ORIGIN - y) + (sz - oz) * (PERSPECTIVE - z) > 0;
}

// A quarter turn as (cos, sin) in steps of about a tenth of a unit along the
// arc, its second half mirrored from its first so left and right sides match
// exactly.
function quarter(radius: number): Flat[] {
  const steps = Math.max(3, Math.ceil(radius / 0.1));
  const half = Array.from({ length: Math.floor(steps / 2) + 1 }, (_, step) => {
    const turn = (Math.PI / 2) * (step / steps);
    return [Math.cos(turn), Math.sin(turn)] as const;
  });
  return Array.from({ length: steps + 1 }, (_, step) =>
    step < half.length ? half[step] : ([half[steps - step][1], half[steps - step][0]] as const),
  );
}

/**
 * The outline of a rounded rectangle from (left, top) to (right, bottom),
 * clockwise from its top right corner, with radii for the top and the bottom
 * corners, and `bottomEdge` run along the bottom from right to left.
 */
function rounded(
  [left, top, right, bottom]: readonly [number, number, number, number],
  [high, low]: readonly [number, number],
  bottomEdge: readonly Flat[] = [],
): Flat[] {
  const [up, down] = [quarter(high), quarter(low)];
  return [
    ...up.map(([c, s]): Flat => [right - high + high * s, top + high - high * c]),
    ...down.map(([c, s]): Flat => [right - low + low * c, bottom - low + low * s]),
    ...bottomEdge,
    ...down.map(([c, s]): Flat => [left + low - low * s, bottom - low + low * c]),
    ...up.map(([c, s]): Flat => [left + high - high * c, top + high - high * s]),
  ];
}

/** The outer outline of points on screen, anticlockwise. */
function hull(points: readonly Flat[]): Flat[] {
  const sorted = [...points].sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  const turn = (o: Flat, a: Flat, b: Flat) => (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
  const chain = (list: readonly Flat[]) => {
    const kept: Flat[] = [];
    for (const point of list) {
      while (kept.length >= 2 && turn(kept[kept.length - 2], kept[kept.length - 1], point) <= 0) {
        kept.pop();
      }
      kept.push(point);
    }
    kept.pop();
    return kept;
  };
  return [...chain(sorted), ...chain(sorted.reverse())];
}

const line = (points: readonly Flat[]) =>
  `M${points.map(([x, y]) => `${cut(x)} ${cut(y)}`).join("L")}`;
const shape = (points: readonly Flat[]) => `${line(points)}Z`;

// The thumb slot cut into the front edge of the base: 56 mm wide, 2.8 mm
// into the deck and 3.6 mm down the front, with a flat floor, rounded ends
// and a small fillet where it leaves the edge.
const NOTCH = 11.8;
const SCOOP = 0.59;
const DIP = 0.76;
const FILLET = 0.15;
const END = 0.6;

/** The slot's outline from left to right, as (across, how far in from the edge). */
function slot(depth: number, end: number): Flat[] {
  const side = NOTCH / 2 - FILLET;
  const fillet = quarter(FILLET);
  const bend = quarter(end);
  const left: Flat[] = [
    ...fillet.map(([c, s]): Flat => [-side - FILLET + FILLET * s, FILLET - FILLET * c]),
    ...bend.map(([c, s]): Flat => [-side + end - end * c, depth - end + end * s]),
  ];
  return [...left, ...[...left].reverse().map(([x, y]): Flat => [-x, y])];
}

const HALF_WIDTH = WIDTH / 2;
const HALF_DEPTH = DEPTH / 2;
const onDeck = ([x, y]: Flat, z = 0) => project([x, y, z]);

// The body of the base: its outline on screen, the deck's top with the slot
// cut into its front edge, and the slot's dip down the front face.
const SLAB: readonly [number, number, number, number] = [-HALF_WIDTH, -HALF_DEPTH, HALF_WIDTH, HALF_DEPTH];
const PLAIN = rounded(SLAB, [ROUND, ROUND]);
const SCOOP_EDGE = slot(SCOOP, SCOOP - FILLET).map(([x, y]): Flat => [x, HALF_DEPTH - y]);
const DIP_EDGE = slot(DIP, END).map(([x, w]) => project([x, HALF_DEPTH, -w]));
const DECK_RING = rounded(SLAB, [ROUND, ROUND], [...SCOOP_EDGE].reverse()).map((point) => onDeck(point));
const BASE_HULL = hull([...PLAIN.map((point) => onDeck(point)), ...PLAIN.map((point) => onDeck(point, -BASE))]);

/** A rounded rectangle on the deck. */
const patch = (box: readonly [number, number, number, number], radius: number) =>
  shape(rounded(box, [radius, radius]).map((point) => onDeck(point)));

// The keyboard well and its keys, in key units across; every row adds up to
// 14.5 with the arrow keys. The well is 58.5 by 23.2, 2.76 behind the deck's
// back edge, and the keys stand 0.44 apart.
const WELL: readonly [number, number, number, number] = [-29.238, -20.595, 29.238, 2.615];
const ROWS: readonly (readonly number[])[] = [
  [1.5, ...Array(12).fill(1), 1],
  [...Array(13).fill(1), 1.5],
  [1.5, ...Array(13).fill(1)],
  [1.75, ...Array(11).fill(1), 1.75],
  [2.25, ...Array(10).fill(1), 2.25],
  [1, 1, 1, 1.25, 5, 1.25, 1],
];
const PAD = 0.3;
const GAP = 0.22;
const UNIT = (WELL[2] - WELL[0] - 2 * PAD) / 14.5;
const ROW = (WELL[3] - WELL[1] - 2 * PAD) / ROWS.length;

type Box = readonly [number, number, number, number];
const KEYS: Box[] = ROWS.flatMap((row, index) => {
  const top = WELL[1] + PAD + index * ROW;
  let left = WELL[0] + PAD;
  return row.map((units): Box => {
    const box: Box = [left + GAP, top + GAP, left + units * UNIT - GAP, top + ROW - GAP];
    left += units * UNIT;
    return box;
  });
});
// Left, up over down, and right, the half-height arrows in the last row.
const ARROW_LEFT = WELL[0] + PAD + 11.5 * UNIT;
const ARROW_TOP = WELL[1] + PAD + 5 * ROW + GAP;
const ARROW_HALF = (ROW - 2 * GAP - 0.2) / 2;
const ARROWS: Box[] = [
  [0, 1],
  [1, 0],
  [1, 1],
  [2, 1],
].map(([column, half]) => {
  const left = ARROW_LEFT + column * UNIT + GAP;
  const top = ARROW_TOP + half * (ARROW_HALF + 0.2);
  return [left, top, left + UNIT - 2 * GAP, top + ARROW_HALF];
});
const TOUCH_ID = KEYS[ROWS[0].length - 1];

// The speaker grilles beside the keyboard, and the trackpad, 27.5 by 17.1.
const GRILLE = 1.1;
const GRILLE_GAP = 0.3;
const GRILLES: Box[] = [-1, 1].map((side) => {
  const inner = side * (WELL[2] + GRILLE_GAP);
  const outer = inner + side * GRILLE;
  return [Math.min(inner, outer), WELL[1] + 0.15, Math.max(inner, outer), WELL[3] - 0.15];
});
const TRACKPAD: Box = [-13.728, 5.23, 13.728, 22.323];

// The grilles' holes, drawn as dotted lines down each grille, HOLE apart on
// screen, every other line half a step lower.
export const HOLE = 0.22;
function holes([left, top, right, bottom]: Box): string {
  const columns = Math.round((right - left) / 0.3);
  return Array.from({ length: columns }, (_, column) => {
    const across = left + (right - left) * ((column + 0.5) / columns);
    const [from, to] = [onDeck([across, top + 0.25]), onDeck([across, bottom - 0.25])];
    const length = Math.hypot(to[0] - from[0], to[1] - from[1]);
    const shift = (column % 2) * (HOLE / 2) / length;
    return line([[from[0] + (to[0] - from[0]) * shift, from[1] + (to[1] - from[1]) * shift], to]);
  }).join("");
}

// The hinge barrel behind the deck, which shows between the deck and the lid.
const BARREL_FACE = [
  [-HINGE_SPAN, 0.3],
  [HINGE_SPAN, 0.3],
  [HINGE_SPAN, -0.2],
  [-HINGE_SPAN, -0.2],
].map(([x, z]) => project([x, -HALF_DEPTH - 0.05, z]));

// The shadow on the ground: the base's footprint, a little in from its edge.
const FOOTPRINT = (spread: number, ahead: number) =>
  shape(
    rounded([-HALF_WIDTH + 1.32 - spread, -HALF_DEPTH + 0.93 - spread + ahead, HALF_WIDTH - 1.32 + spread, HALF_DEPTH - 0.93 + spread + ahead], [ROUND, ROUND]).map(
      (point) => onDeck(point, -BASE - 0.1),
    ),
  );

/** Everything that never moves, as SVG path data in the scene's units. */
export const DECK = {
  hull: shape(BASE_HULL),
  top: shape(DECK_RING),
  lines: `${shape(BASE_HULL)}${shape(DECK_RING)}${line(DIP_EDGE)}`,
  scoop: shape([...SCOOP_EDGE.map((point) => onDeck(point)), ...[...DIP_EDGE].reverse()]),
  well: patch(WELL, 0.8),
  keys: [...KEYS.filter((key) => key !== TOUCH_ID), ...ARROWS]
    .map((key) => patch(key, key[3] - key[1] < 2 ? 0.25 : 0.38))
    .join(""),
  touchId: patch(TOUCH_ID, 0.38),
  touchIdRing: patch([TOUCH_ID[0] + 0.45, TOUCH_ID[1] + 0.45, TOUCH_ID[2] - 0.45, TOUCH_ID[3] - 0.45], 0.3),
  grilles: GRILLES.map((box) => patch(box, 0.3)).join(""),
  holes: GRILLES.map(holes).join(""),
  trackpad: patch(TRACKPAD, 1),
  barrel: shape(BARREL_FACE),
  contact: FOOTPRINT(0, 0.3),
  ground: FOOTPRINT(0.8, 1.2),
};

// The lid's outline in its own plane, x across and d up from the hinge.
const LID_RING = rounded([-HALF_WIDTH, -DEPTH, HALF_WIDTH, 0], [ROUND, HINGE_ROUND]);
const BEZEL_RING = rounded(
  [-HALF_WIDTH + RIM, -DEPTH + RIM, HALF_WIDTH - RIM, -RIM],
  [ROUND - RIM, HINGE_ROUND - RIM],
);
const HINGE_RING = rounded([-HINGE_SPAN, -HINGE, HINGE_SPAN, 0], [HINGE / 2, HINGE / 2]);

/** The lid's angle at the hinge in degrees, from OPEN to -180 when shut. */
export const lidAngle = (closed: number) => OPEN - (180 + OPEN) * closed;

/** The lid's paths for one frame, `closed` from 0 (open) to 1 (shut on the base). */
export function lidArt(closed: number) {
  const angle = lidAngle(closed) * RADIAN;
  const [cos, sin] = [Math.cos(angle), Math.sin(angle)];
  // A point `behind` the display's face, at (x, -d) in the lid's plane.
  const at = (behind: number) => ([x, up]: Flat): Solid => [x, -HALF_DEPTH + up * cos + behind * sin, LIFT + up * sin - behind * cos];
  const flat = (behind: number, ring: readonly Flat[]) => ring.map((point) => project(at(behind)(point)));
  // Shut, the lid's sides reach down to the deck, so the seam is one line.
  const skirt = LIFT * Math.min(1, Math.max(0, (closed - 0.9) / 0.1));
  const front = flat(0, LID_RING);
  const back = flat(LID, LID_RING);
  const outline = hull([...front, ...back, ...(skirt > 0 ? flat(-skirt, LID_RING) : [])]);
  const facing = facesEye(at(0)([0, -DEPTH / 2]), [0, -sin, cos]);
  const face = facing ? front : back;
  // How far over the deck the lid reaches, as a share of its depth, for its shadow.
  const reach = Math.max(0, -cos);
  return {
    facing,
    hull: shape(outline),
    face: shape(face),
    bezel: facing ? shape(flat(0, BEZEL_RING)) : null,
    hinge: facing ? shape(flat(0, HINGE_RING)) : null,
    lines: `${shape(outline)}${shape(face)}`,
    shadow:
      closed > 0
        ? {
            from: cut(onDeck([0, -HALF_DEPTH + DEPTH * (reach - 0.1)])[1]),
            to: cut(onDeck([0, -HALF_DEPTH + DEPTH * (reach + 0.15)])[1]),
          }
        : null,
  };
}
