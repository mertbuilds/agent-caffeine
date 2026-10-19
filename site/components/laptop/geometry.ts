// A 14 inch MacBook Pro: 312.6 mm wide, 221.2 mm deep and 15.5 mm thick, of
// which the lid is about 4.5 mm. Sizes are hundredths of the scene's width,
// at 66 for the width, in a scene 100 wide. The display is 302.5 by
// 196.5 mm inside a 5 mm bezel.
export const WIDTH = 66;
export const DEPTH = 46.7;
const BASE = 2.3;
const LID = 0.95;
export const BEZEL = 1.07;
export const CHIN = 4.15;
// The lid stands LIFT above the deck. An eye sits `perspective` away, level
// with `origin`; the laptop stands `back` behind its focus at `anchor` and
// turns towards it by `camera` degrees, in a scene 100 by `height`. The
// scene's CSS (hero-scene.tsx and the glass in laptop.tsx) uses the same
// numbers.
export const LIFT = 0.15;
type Eye = { id: string; height: number; perspective: number; camera: number; back: number; origin: number; anchor: number };
// The corners of both slabs, and the aluminium rim round the display glass.
export const ROUND = 2.1;
const RIM = 0.25;
// The lid turns about an axis 2.9 mm in from the base's back edge and 4.6 mm
// under the shut lid's face, so open its chin drops behind the base towards
// the table. The hinge fills a cut 237.6 mm wide and 4.5 mm deep in the
// base's back edge, between shoulders of 37.5 mm: an aluminium barrel 15 mm
// long at each end and the dark cover between them.
const PIVOT: Flat = [0.62, -0.98];
const CUT = 50.16;
const CUT_DEPTH = 0.94;
const CUT_ROUND = 0.12;
const BARREL = 3.16;

type Flat = readonly [number, number];
type Solid = readonly [number, number, number];

/**
 * A computed number cut to 4 decimals, and -0 to 0, so markup reads the same
 * from the server's HTML as from the client.
 */
export const fixed = (value: number) => Math.round(value * 1e4) / 1e4 || 0;
const cut = (value: number) => Math.round(value * 100) / 100 || 0;

/** One dot of the speaker grilles. */
export const HOLE = 0.085;

/** The laptop as one eye sees it: what never moves, and the lid for each frame. */
function seen({ id, height, perspective: PERSPECTIVE, camera: CAMERA, back: BACK, origin: ORIGIN, anchor: ANCHOR }: Eye) {
  // The open lid faces the eye, so its glass is a plain rectangle on screen.
  const OPEN = -90 - CAMERA;
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
   * corners, `bottomEdge` run along the bottom from right to left and `topEdge`
   * along the top from left to right.
   */
  function rounded(
    [left, top, right, bottom]: readonly [number, number, number, number],
    [high, low]: readonly [number, number],
    bottomEdge: readonly Flat[] = [],
    topEdge: readonly Flat[] = [],
  ): Flat[] {
    const [up, down] = [quarter(high), quarter(low)];
    return [
      ...up.map(([c, s]): Flat => [right - high + high * s, top + high - high * c]),
      ...down.map(([c, s]): Flat => [right - low + low * c, bottom - low + low * s]),
      ...bottomEdge,
      ...down.map(([c, s]): Flat => [left + low - low * s, bottom - low + low * c]),
      ...up.map(([c, s]): Flat => [left + high - high * c, top + high - high * s]),
      ...topEdge,
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

  /** A slot's outline from left to right, as (across, how far in from the edge). */
  function slot(width: number, depth: number, end: number): Flat[] {
    const side = width / 2 - FILLET;
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
  // cut into its front edge and the hinge's cut into its back edge, and the
  // slot's dip down the front face.
  const SLAB: readonly [number, number, number, number] = [-HALF_WIDTH, -HALF_DEPTH, HALF_WIDTH, HALF_DEPTH];
  const PLAIN = rounded(SLAB, [ROUND, ROUND]);
  const SCOOP_EDGE = slot(NOTCH, SCOOP, SCOOP - FILLET).map(([x, y]): Flat => [x, HALF_DEPTH - y]);
  const DIP_EDGE = slot(NOTCH, DIP, END).map(([x, w]) => project([x, HALF_DEPTH, -w]));
  const CUT_EDGE = slot(CUT, CUT_DEPTH, CUT_ROUND).map(([x, y]): Flat => [x, y - HALF_DEPTH]);
  const DECK_RING = rounded(SLAB, [ROUND, ROUND], [...SCOOP_EDGE].reverse(), CUT_EDGE).map((point) => onDeck(point));
  const BASE_HULL = hull([...PLAIN.map((point) => onDeck(point)), ...PLAIN.map((point) => onDeck(point, -BASE))]);
  // The base's outline without its back edge, which the deck's top draws with the cut.
  const BACK_EDGE = BASE_HULL.reduce(
    (back, [, y], index) => (y + BASE_HULL[(index + 1) % BASE_HULL.length][1] < BASE_HULL[back][1] + BASE_HULL[(back + 1) % BASE_HULL.length][1] ? index : back),
    0,
  );
  const BASE_LINE = [...BASE_HULL.slice(BACK_EDGE + 1), ...BASE_HULL.slice(0, BACK_EDGE + 1)];

  /** A rounded rectangle on the deck. */
  const patch = (box: readonly [number, number, number, number], radius: number) =>
    shape(rounded(box, [radius, radius]).map((point) => onDeck(point)));

  // The keyboard well and its keys, in key units across; every row adds up to
  // 14.5 with the arrow keys. The well is 279.6 by 114.9 mm, 16.6 mm in from the
  // deck's back edge, and the keys stand 0.44 apart.
  const WELL: readonly [number, number, number, number] = [-29.516, -19.845, 29.516, 4.435];
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

  // The trackpad, 129.6 by 80.9 mm, 3 mm under the well.
  const TRACKPAD: Box = [-13.68, 5.07, 13.68, 22.17];

  // The speaker grilles' holes, a square grid centred in the deck beside the
  // keyboard, 1.6 mm from its side edge and from the well and 4.5 mm short of
  // the well's ends. The machine has 15 holes across at 0.93 mm; down the deck,
  // which the eye sees foreshortened, they stand 2.3 mm apart so they are as far
  // apart on screen. Each is one dot HOLE wide.
  const GRILLE_GAP = 0.34;
  const GRILLE_END = 0.95;
  function holes(columns: number, rows: number): string {
    return [-1, 1]
      .flatMap((side) =>
        Array.from({ length: rows * columns }, (_, index) => {
          const across = WELL[2] + GRILLE_GAP + ((HALF_WIDTH - WELL[2] - 2 * GRILLE_GAP) * (index % columns)) / (columns - 1);
          const along = WELL[1] + GRILLE_END + ((WELL[3] - WELL[1] - 2 * GRILLE_END) * Math.floor(index / columns)) / (rows - 1);
          const [x, y] = onDeck([side * across, along]);
          return `M${cut(x)} ${cut(y)}h0`;
        }),
      )
      .join("");
  }

  // The shadow on the ground: the base's footprint, a little in from its edge.
  const FOOTPRINT = (spread: number, ahead: number) =>
    shape(
      rounded([-HALF_WIDTH + 1.32 - spread, -HALF_DEPTH + 0.93 - spread + ahead, HALF_WIDTH - 1.32 + spread, HALF_DEPTH - 0.93 + spread + ahead], [ROUND, ROUND]).map(
        (point) => onDeck(point, -BASE - 0.1),
      ),
    );

  /** Everything that never moves, as SVG path data in the scene's units. */
  const DECK = {
    hull: shape(BASE_HULL),
    top: shape(DECK_RING),
    lines: `${line(BASE_LINE)}${shape(DECK_RING)}${line(DIP_EDGE)}`,
    scoop: shape([...SCOOP_EDGE.map((point) => onDeck(point)), ...[...DIP_EDGE].reverse()]),
    well: patch(WELL, 0.8),
    keys: [...KEYS.filter((key) => key !== TOUCH_ID), ...ARROWS]
      .map((key) => patch(key, key[3] - key[1] < 2 ? 0.25 : 0.38))
      .join(""),
    touchId: patch(TOUCH_ID, 0.38),
    touchIdRing: patch([TOUCH_ID[0] + 0.45, TOUCH_ID[1] + 0.45, TOUCH_ID[2] - 0.45, TOUCH_ID[3] - 0.45], 0.3),
    // The same field of holes at full, half and quarter density, for scenes
    // too small to keep the finer ones apart.
    holes: [holes(15, 47), holes(8, 24), holes(4, 12)],
    trackpad: patch(TRACKPAD, 1),
    // The hinge in its cut, a little past the cut's edges so the deck's top and
    // the lid overlap it.
    hinge: patch([-CUT / 2, -HALF_DEPTH - 0.15, CUT / 2, -HALF_DEPTH + CUT_DEPTH + 0.3], 0),
    barrels: [-CUT / 2, CUT / 2 - BARREL]
      .map((left) => patch([left, -HALF_DEPTH - 0.15, left + BARREL, -HALF_DEPTH + CUT_DEPTH + 0.3], 0))
      .join(""),
    contact: FOOTPRINT(0, 0.3),
    ground: FOOTPRINT(0.8, 1.2),
  };

  /**
   * The part of a closed outline where `side` is not above 0, cut where it
   * crosses, with `between` the point a share of the way from one point to the
   * next.
   */
  function keep<P extends readonly number[]>(
    points: readonly P[],
    side: (point: P) => number,
    between: (from: P, to: P, share: number) => P,
  ): P[] {
    return points.flatMap((point, index) => {
      const next = points[(index + 1) % points.length];
      const [here, there] = [side(point), side(next)];
      const kept = here <= 0 ? [point] : [];
      return here * there < 0 ? [...kept, between(point, next, here / (here - there))] : kept;
    });
  }
  const flatToward = ([x, y]: Flat, [tx, ty]: Flat, share: number): Flat => [x + (tx - x) * share, y + (ty - y) * share];
  const solidToward = ([x, y, z]: Solid, [tx, ty, tz]: Solid, share: number): Solid => [
    x + (tx - x) * share,
    y + (ty - y) * share,
    z + (tz - z) * share,
  ];

  // Which way round `hull` runs, as the sign of its outlines' area.
  const TURN = Math.sign(
    BASE_HULL.reduce((sum, [x, y], index) => {
      const [nx, ny] = BASE_HULL[(index + 1) % BASE_HULL.length];
      return sum + x * ny - nx * y;
    }, 0),
  );

  /** A hull's outline moved out by `distance` all round. */
  function grow(points: readonly Flat[], distance: number): Flat[] {
    const out = ([ax, ay]: Flat, [bx, by]: Flat): Flat => {
      const length = Math.hypot(bx - ax, by - ay);
      return [(TURN * (by - ay)) / length, (-TURN * (bx - ax)) / length];
    };
    return points.map((point, index) => {
      const first = out(points[(index + points.length - 1) % points.length], point);
      const second = out(point, points[(index + 1) % points.length]);
      const [mx, my] = [first[0] + second[0], first[1] + second[1]];
      const length = Math.hypot(mx, my);
      const reach = distance / ((mx * first[0] + my * first[1]) / length);
      return [point[0] + (mx / length) * reach, point[1] + (my / length) * reach];
    });
  }

  // The base's outline on screen grown by half a hairline, so the lid stops at
  // the deck's line instead of covering half of it.
  const GROWN_HULL = grow(BASE_HULL, 0.06);

  /** What of a hull on screen, grown past its hairline, the base covers. */
  function behindBase(points: readonly Flat[]): Flat[] {
    return GROWN_HULL.reduce<Flat[]>((kept, [ax, ay], index) => {
      const [bx, by] = GROWN_HULL[(index + 1) % GROWN_HULL.length];
      return keep(kept, ([x, y]) => -TURN * ((bx - ax) * (y - ay) - (by - ay) * (x - ax)), flatToward);
    }, grow(points, 0.2));
  }

  // The lid's outline in its own plane, x across and d up from the hinge.
  const LID_RING = rounded([-HALF_WIDTH, -DEPTH, HALF_WIDTH, 0], [ROUND, ROUND]);
  const BEZEL_RING = rounded([-HALF_WIDTH + RIM, -DEPTH + RIM, HALF_WIDTH - RIM, -RIM], [ROUND - RIM, ROUND - RIM]);

  /**
   * The lid's place for one frame, `closed` from 0 (open) to 1 (shut on the
   * base): its angle in degrees, from OPEN to -180 when shut, about the back
   * edge of the shut lid's face, then how far it moves along the deck and up
   * for the hinge's real axis.
   */
  function lidPose(closed: number) {
    const angle = OPEN - (180 + OPEN) * closed;
    const turn = (angle + 180) * RADIAN;
    const [y, z] = PIVOT;
    return {
      angle,
      along: y * (1 - Math.cos(turn)) + z * Math.sin(turn),
      up: z * (1 - Math.cos(turn)) - y * Math.sin(turn),
    };
  }

  /** The lid's paths for one frame, `closed` from 0 (open) to 1 (shut on the base). */
  function lidArt(closed: number) {
    const pose = lidPose(closed);
    const angle = pose.angle * RADIAN;
    const [cos, sin] = [Math.cos(angle), Math.sin(angle)];
    // A point `behind` the display's face, at (x, -d) in the lid's plane.
    const at = (behind: number) => ([x, up]: Flat): Solid => [
      x,
      -HALF_DEPTH + pose.along + up * cos + behind * sin,
      LIFT + pose.up + up * sin - behind * cos,
    ];
    const flat = (behind: number, ring: readonly Flat[]) => ring.map((point) => project(at(behind)(point)));
    // Shut, the lid's sides reach down to the deck, so the seam is one line.
    const skirt = LIFT * Math.min(1, Math.max(0, (closed - 0.9) / 0.1));
    const front = flat(0, LID_RING);
    const back = flat(LID, LID_RING);
    const outline = hull([...front, ...back, ...(skirt > 0 ? flat(-skirt, LID_RING) : [])]);
    const facing = facesEye(at(0)([0, -DEPTH / 2]), [0, -sin, cos]);
    const face = facing ? front : back;
    // The chin below the deck drops behind the base, which hides it where the
    // rest of the lid does not stand in front.
    const part = (side: number) =>
      [0, LID].flatMap((behind) => keep(LID_RING.map(at(behind)), ([, , z]) => side * z, solidToward).map(project));
    const sunk = part(1);
    const hidden = sunk.length > 2 ? behindBase(hull(sunk)) : [];
    // How far over the deck the lid reaches, as a share of its depth, for its shadow.
    const reach = Math.max(0, -cos);
    return {
      facing,
      hull: shape(outline),
      face: shape(face),
      bezel: facing ? shape(flat(0, BEZEL_RING)) : null,
      cut: hidden.length > 2 ? { hidden: shape(hidden), clear: shape(grow(hull(part(-1)), 0.08)) } : null,
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

  return { id, height, PERSPECTIVE, CAMERA, BACK, ORIGIN, ANCHOR, DECK, lidPose, lidArt };
}

export type View = ReturnType<typeof seen>;

/** Beside the words, on a wide page: the eye is near, so the deck comes forward and spreads. The lid opens to 105 degrees. */
export const DESK = seen({ id: "desk", height: 70, perspective: 200, camera: -15, back: 14, origin: 0.22 * 70, anchor: 0.78 * 70 });

/**
 * Over the words, on a phone: the eye is three times as far and a little
 * lower, so the deck is hardly wider than the lid and half as deep, and the
 * whole laptop fits a narrow page. `back` and `anchor` put the open lid where
 * DESK has it, so one glass serves both. The lid opens to 102 degrees.
 */
export const PHONE = seen({ id: "phone", height: 59, perspective: 600, camera: -12, back: 88.07, origin: 0.22 * 70, anchor: 53.43 });
