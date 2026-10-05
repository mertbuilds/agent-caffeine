import type { CSSProperties, ReactNode } from "react";

// A 14 inch MacBook Pro: 312.6 mm wide, 221.2 mm deep and 15.5 mm thick, of
// which the lid is about 4.5 mm. Sizes are hundredths of the scene's width,
// at 66 for the width. The display is 302.5 by 196.5 mm inside a 5 mm bezel.
const WIDTH = 66;
const DEPTH = 46.7;
const BASE = 2.3;
const LID = 0.95;
const BEZEL = 1.07;
const CHIN = 4.15;
// The lid opens to 105 degrees. The scene's camera sits 200 hundredths away
// (about a 70 mm lens); the laptop stands 14 behind its focus and turns 15
// degrees towards it, which with the eye above it shows the deck from about 25.
const OPEN = -75;
const CAMERA = -15;
const BACK = 14;
// The corners of both slabs, the aluminium rim around the display glass, and
// the hinge barrel under the display.
const ROUND = 2.1;
const RIM = 0.25;
const HINGE = 0.8;

/**
 * A computed number cut to 4 decimals, and -0 to 0, so a style reads the same
 * from the server's HTML as from the client: the browser keeps 6 significant
 * digits of a CSS number, and every size here is under 100.
 */
const fixed = (value: number) => Math.round(value * 1e4) / 1e4 || 0;
const cq = (size: number) => `${fixed(size)}cqw`;

// Key widths in units; every row adds up to 14.5 with the arrow keys.
const ROWS: readonly (readonly number[])[] = [
  [1.5, ...Array(12).fill(1), 1],
  [...Array(13).fill(1), 1.5],
  [1.5, ...Array(13).fill(1)],
  [1.75, ...Array(11).fill(1), 1.75],
  [2.25, ...Array(10).fill(1), 2.25],
  [1, 1, 1, 1.25, 5, 1.25, 1],
];
// Left, up over down, right: the arrow keys in one row height.
const ARROWS = [
  [false, true],
  [true, true],
  [false, true],
] as const;

/** The page's shadow, thinned, so a tone steps down the same way in light and dark. */
const shade = (share: number) => `color-mix(in srgb, var(--shadow) ${share}%, transparent)`;
const toned = (share: number) => `linear-gradient(${shade(share)}, ${shade(share)}), var(--surface)`;

// Anodised aluminium in close tones: the deck is the page's surface, the sides
// a step darker, the rim round the glass a step towards the border, and the
// lid's shell a faint sheen. The hinge barrel is near black, like the glass.
const SIDE = toned(45);
const RIM_TONE = "color-mix(in srgb, var(--surface) 60%, var(--border))";
const SHEEN =
  "linear-gradient(160deg, color-mix(in srgb, var(--surface) 25%, var(--bg)), var(--surface) 55%, color-mix(in srgb, var(--surface) 50%, var(--bg)))";
const BARREL = "color-mix(in srgb, var(--hairline) 15%, black)";

const outline: CSSProperties = { borderColor: "var(--hairline)" };
// Seen from above, a line across a level plane shows at under half its
// width, so the front and back edges are drawn twice as wide as the sides.
const flat = "border border-y-2";
const key = "rounded-[0.38cqw] border border-[var(--border)] bg-[var(--surface)]";

/** The outline down each side of a slab, where its rounded front corners turn away. */
function Edges({ top, thickness }: { top: number; thickness: number }) {
  return (["left", "right"] as const).map((side) => (
    <div
      key={side}
      className="absolute w-px bg-[var(--hairline)]"
      style={{
        [side]: 0,
        top: cq(top),
        height: cq(thickness),
        transformOrigin: "top",
        transform: "rotateX(-90deg)",
      }}
    />
  ));
}

// Points along the quarter round at a front corner, from the side of the slab
// to its front, which flat strips join.
const SEGMENTS = 12;
const ARC = Array.from({ length: SEGMENTS + 1 }, (_, index) => {
  const turn = (Math.PI / 2) * (index / SEGMENTS);
  return [ROUND * (1 - Math.cos(turn)), ROUND * Math.sin(turn)] as const;
});

/**
 * The upright faces across the front of a slab and round its two front
 * corners, `thickness` deep below its top. `front` is where the front edge
 * runs across the plane; `toward` is 1 when the front is the plane's bottom
 * edge and -1 when it is the top. The faces stand just inside the outline of
 * the planes above and below, so they never cover it.
 */
function Walls({ front, toward, thickness }: { front: number; toward: 1 | -1; thickness: number }) {
  const inset = (y: number) => `calc(${cq(y)} ${toward > 0 ? "-" : "+"} 2px)`;
  const strips = [false, true].flatMap((right) =>
    ARC.slice(1).map(([x1, y1], index) => {
      const [x0, y0] = ARC[index];
      const from = [right ? WIDTH - x0 : x0, front - toward * (ROUND - y0)];
      const to = [right ? WIDTH - x1 : x1, front - toward * (ROUND - y1)];
      const [dx, dy] = [to[0] - from[0], to[1] - from[1]];
      return { key: `${right}-${index}`, right, from, length: Math.hypot(dx, dy), turn: Math.atan2(dy, dx) };
    }),
  );
  return (
    <>
      {strips.map(({ key, right, from, length, turn }) => (
        <div
          key={key}
          className="absolute"
          style={{
            background: SIDE,
            left: `calc(${cq(from[0])} ${right ? "-" : "+"} 1px)`,
            top: inset(from[1]),
            width: `calc(${cq(length)} + 0.5px)`,
            height: cq(thickness),
            transformOrigin: "0 0",
            transform: `rotateZ(${fixed(turn)}rad) rotateX(-90deg)`,
          }}
        />
      ))}
      <div
        className="absolute"
        style={{
          background: SIDE,
          left: cq(ROUND),
          top: inset(front),
          width: cq(WIDTH - 2 * ROUND),
          height: cq(thickness),
          transformOrigin: "top",
          transform: "rotateX(-90deg)",
        }}
      />
      <Edges top={front - toward * ROUND} thickness={thickness} />
    </>
  );
}

function Keyboard() {
  return (
    <div
      className="absolute inset-x-[5.7%] top-[5.9%] flex h-[49.7%] flex-col rounded-[0.8cqw] border border-[var(--border)] p-[0.2cqw]"
      style={{ background: shade(50) }}
    >
      {ROWS.map((row, index) => (
        <div key={index} className="flex flex-1">
          {row.map((grow, column) => (
            <div key={column} className="p-[0.22cqw]" style={{ flexGrow: grow, flexBasis: 0 }}>
              <div className={`h-full ${key}`} />
            </div>
          ))}
          {index === ROWS.length - 1 &&
            ARROWS.map((cells, column) => (
              <div key={`arrow-${column}`} className="flex flex-1 flex-col gap-[0.2cqw] p-[0.22cqw]">
                {cells.map((shown, cell) => (
                  <div key={cell} className={shown ? `flex-1 ${key}` : "flex-1"} />
                ))}
              </div>
            ))}
        </div>
      ))}
    </div>
  );
}

// The thumb slot cut into the front edge of the base: 56 mm wide, 2.8 mm
// into the deck and 3.6 mm down the front, with a flat floor, rounded ends
// and a small fillet where it leaves the edge.
const NOTCH = 11.8;
const SCOOP = 0.59;
const DIP = 0.76;
const FILLET = 0.15;
const END = 0.6;

/**
 * The slot's outline across a box NOTCH wide, from the edge at `from` to its
 * floor at `to`, with every x times `stretch`. Each quarter turn is a cubic
 * that leaves and meets its straights level, so the line has no corners.
 */
function slot(stretch: number, from: number, to: number, round: number): string {
  const k = 0.5523;
  const s = Math.sign(to - from);
  const p = (x: number, y: number) => `${fixed(x * stretch)} ${fixed(y)}`;
  const [left, right] = [FILLET, NOTCH - FILLET];
  const [near, far] = [from + s * FILLET, to - s * round];
  return [
    `M${p(0, from)}`,
    `C${p(k * FILLET, from)} ${p(left, near - s * k * FILLET)} ${p(left, near)}`,
    `L${p(left, far)}`,
    `C${p(left, far + s * k * round)} ${p(left + round - k * round, to)} ${p(left + round, to)}`,
    `L${p(right - round, to)}`,
    `C${p(right - round + k * round, to)} ${p(right, far + s * k * round)} ${p(right, far)}`,
    `L${p(right, near)}`,
    `C${p(right, near - s * k * FILLET)} ${p(NOTCH - k * FILLET, from)} ${p(NOTCH, from)}`,
  ].join("");
}
const SCOOP_EDGE = slot(2, SCOOP, 0, SCOOP - FILLET);
const DIP_EDGE = slot(1, 0, DIP, END);

/** The scoop's face: `fill` in the scoop's tone, outlined along `edge` only, `line` pixels wide. */
function Scoop({ fill, edge, line }: { fill: string; edge: string; line: number }) {
  return (
    <>
      <path d={fill} style={{ fill: "var(--surface)" }} />
      <path d={fill} style={{ fill: "var(--shadow)" }} />
      <path d={edge} fill="none" vectorEffect="non-scaling-stroke" strokeWidth={line} style={{ stroke: "var(--hairline)" }} />
    </>
  );
}

const slab = "rounded-[2.1cqw]";
const lid = "rounded-b-[0.4cqw] rounded-t-[2.1cqw]";

/** The top of the base, with everything on it. */
const DECK_TOP = (
  <>
    <Keyboard />
    <div
      className="absolute inset-x-[29.2%] bottom-[2.2%] h-[36.6%] rounded-[1cqw] border border-[var(--border)]"
      style={{ background: shade(20) }}
    />
    {/* The scoop's top, over the front outline. Drawn twice as wide and squeezed, its line is 2px across and 1px along, like the outline's. */}
    <div
      className="absolute left-1/2 overflow-hidden"
      style={{ bottom: "-2px", width: cq(NOTCH), marginLeft: cq(-NOTCH / 2), height: `calc(${cq(SCOOP)} + 3px)` }}
    >
      <svg
        viewBox={`0 0 ${fixed(2 * NOTCH)} ${SCOOP}`}
        preserveAspectRatio="none"
        aria-hidden="true"
        className="absolute bottom-px left-[-50%] w-[200%] scale-x-50 overflow-visible"
        style={{ height: cq(SCOOP) }}
      >
        <Scoop fill={`${SCOOP_EDGE}V${3 * SCOOP}H0Z`} edge={SCOOP_EDGE} line={2} />
      </svg>
    </div>
  </>
);

/** The body of the base under its top, which never changes as the lid moves. */
const DECK = (
  <>
    <div
      className={`absolute inset-[2%] ${slab}`}
      style={{
        transform: `translateZ(${cq(-BASE - 0.1)})`,
        boxShadow: `0 ${cq(0.3)} ${cq(0.8)} var(--shadow), 0 ${cq(1.2)} ${cq(4)} ${cq(0.8)} var(--shadow)`,
      }}
    />
    <div
      className={`absolute inset-0 ${slab} ${flat}`}
      style={{ ...outline, background: SIDE, transform: `translateZ(${cq(-BASE)})` }}
    />
    <Walls front={DEPTH} toward={1} thickness={BASE} />
    {/* The hinge barrel behind the deck, which shows under the lid. */}
    <div
      className="absolute"
      style={{
        background: BARREL,
        left: cq(ROUND),
        top: cq(-0.05),
        width: cq(WIDTH - 2 * ROUND),
        height: cq(0.5),
        transformOrigin: "top",
        transform: `translateZ(${cq(0.3)}) rotateX(-90deg)`,
      }}
    />
    <svg
      viewBox={`0 0 ${NOTCH} ${DIP}`}
      preserveAspectRatio="none"
      aria-hidden="true"
      className="absolute overflow-visible"
      style={{
        left: cq((WIDTH - NOTCH) / 2),
        top: cq(DEPTH),
        width: cq(NOTCH),
        height: cq(DIP),
        transformOrigin: "top",
        transform: `rotateX(-90deg) translateZ(${cq(0.02)})`,
      }}
    >
      <Scoop fill={`${DIP_EDGE}Z`} edge={DIP_EDGE} line={1} />
    </svg>
  </>
);

/** The front of the lid: the aluminium rim, the black glass and the hinge barrel under it. */
function Display({ children }: { children: ReactNode }) {
  return (
    <div
      className={`absolute inset-0 ${lid} border [backface-visibility:hidden]`}
      style={{ ...outline, background: RIM_TONE, padding: cq(RIM) }}
    >
      <div
        className="h-full bg-black"
        style={{
          borderRadius: `${cq(ROUND - RIM)} ${cq(ROUND - RIM)} ${cq(0.4 - RIM)} ${cq(0.4 - RIM)}`,
          padding: `${cq(BEZEL - RIM)} ${cq(BEZEL - RIM)} ${cq(CHIN - RIM)}`,
        }}
      >
        <div
          className="relative h-full overflow-hidden bg-[#0d0d0d] [container-type:inline-size]"
          style={{ borderRadius: `${cq(ROUND - BEZEL)} ${cq(ROUND - BEZEL)} 0 0` }}
        >
          {children}
          <div
            className="absolute inset-0"
            style={{ background: "linear-gradient(110deg, color-mix(in srgb, var(--hairline) 9%, transparent), transparent 35%)" }}
          />
          <div className="absolute left-1/2 top-0 h-[3.6%] w-[12.5%] -translate-x-1/2 rounded-b-[0.8cqw] bg-black" />
        </div>
      </div>
      <div
        className="absolute bottom-[-1px] rounded-[0.4cqw]"
        style={{
          left: cq(ROUND),
          right: cq(ROUND),
          height: cq(HINGE),
          background: `linear-gradient(color-mix(in srgb, var(--hairline) 45%, black), ${BARREL})`,
        }}
      />
    </div>
  );
}

/** The back of the lid behind the display, which never changes as the lid moves. */
const LID_BACK = (
  <>
    <Walls front={0} toward={-1} thickness={LID} />
    <div
      className={`absolute inset-0 ${lid} ${flat}`}
      style={{ ...outline, background: SHEEN, transform: `translateZ(${cq(-LID)})` }}
    />
  </>
);

type LaptopProps = {
  /** How far the lid has closed, from 0 (open) to 1 (shut on the base). */
  closed: number;
  /** How bright the display is, from 0 (off) to 1. */
  display: number;
  children: ReactNode;
};

/** A MacBook drawn in CSS 3D, seen from the front and a little above, with `children` on its display. */
export function Laptop({ closed, display, children }: LaptopProps) {
  const angle = OPEN - (180 + OPEN) * closed;
  // How far over the deck the lid reaches, as a share of its depth.
  const reach = Math.max(0, Math.cos(((180 + angle) * Math.PI) / 180));

  return (
    <div
      className="absolute left-1/2 top-[78%] [transform-style:preserve-3d]"
      style={{ transform: `translateZ(${cq(-BACK)}) rotateX(${CAMERA}deg)` }}
    >
      <div
        className="absolute [transform-style:preserve-3d]"
        style={{
          width: cq(WIDTH),
          height: cq(DEPTH),
          left: cq(-WIDTH / 2),
          top: cq(-DEPTH / 2),
          transform: "rotateX(90deg)",
        }}
      >
        {DECK}
        <div className={`absolute inset-0 ${slab} ${flat} bg-[var(--surface)]`} style={outline}>
          {DECK_TOP}
          {closed > 0 && (
            <div className="absolute inset-0 overflow-hidden rounded-[calc(2.1cqw-1px)]">
              <div
                className="h-full"
                style={{
                  background: "linear-gradient(var(--shadow) 75%, transparent)",
                  opacity: fixed(closed),
                  transform: `translateY(${fixed((reach - 0.85) * 100)}%)`,
                }}
              />
            </div>
          )}
        </div>
        <div
          className="absolute left-0 [transform-style:preserve-3d]"
          style={{
            top: cq(-DEPTH),
            width: cq(WIDTH),
            height: cq(DEPTH),
            transformOrigin: "bottom",
            transform: `translateZ(0.15cqw) rotateX(${fixed(angle)}deg)`,
          }}
        >
          <Display>
            <div className="h-full" style={{ opacity: fixed(display) }}>
              {children}
            </div>
          </Display>
          {/* The underside of the lid. Its outline fades as the lid shuts, so the seam is the deck's one line. */}
          <div className={`absolute inset-0 ${lid}`} style={{ background: SIDE, transform: `translateZ(${cq(-0.08)})` }}>
            <div className={`absolute inset-0 ${lid} ${flat}`} style={{ ...outline, opacity: fixed(Math.min(1, (1 - closed) * 20)) }} />
          </div>
          {LID_BACK}
        </div>
      </div>
    </div>
  );
}
