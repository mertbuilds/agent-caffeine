import { useMemo, type CSSProperties, type ReactNode } from "react";
import {
  BACK,
  BEZEL,
  CAMERA,
  CHIN,
  DECK,
  DEPTH,
  HOLE,
  LIFT,
  ROUND,
  WIDTH,
  fixed,
  lidArt,
  lidPose,
} from "./geometry";

const cq = (size: number) => `${fixed(size)}cqw`;

// Anodised aluminium in close tones, lit from above: the tops are the page's
// surface, the sides a step darker under the page's shadow, the rim round the
// glass a step towards the border, and the shut lid an even tone. The glass,
// the hinge cover and the keyboard are near black, as on the machine, and the
// hinge's barrels a darker aluminium in the shade of the lid.
const SURFACE: CSSProperties = { fill: "var(--surface)" };
const shade = (share: number): CSSProperties => ({ fill: "var(--shadow)", fillOpacity: share });
const SIDE = 0.45;
const RIM_TONE = "color-mix(in srgb, var(--surface) 60%, var(--border))";
const LENS = "color-mix(in srgb, var(--hairline) 15%, black)";
const HINGE = "color-mix(in srgb, var(--hairline) 6%, black)";
const BARREL = "color-mix(in srgb, var(--surface) 78%, black)";
const WELL = "color-mix(in srgb, var(--surface) 10%, black)";
const KEY = `color-mix(in srgb, var(--hairline) 22%, ${WELL})`;
const TOUCH_ID = `color-mix(in srgb, var(--hairline) 12%, ${WELL})`;

const hairline = (color: string): CSSProperties => ({ stroke: color, fill: "none" });
const stroke = {
  vectorEffect: "non-scaling-stroke",
  strokeWidth: 1,
  strokeLinejoin: "round",
  strokeLinecap: "round",
} as const;

// Which field of holes shows: the full one where a hole is about a device
// pixel (a scene 560px wide at two pixels a px), the half one down to half
// that, the quarter one below.
const HOLES_SHOWN = [
  "hidden [@media(min-resolution:2dppx)]:[@container(min-width:560px)]:inline",
  "[@media(min-resolution:2dppx)]:[@container(min-width:560px)]:hidden [@media(max-resolution:1.99dppx)]:[@container(max-width:559.98px)]:hidden [@container(max-width:279.98px)]:hidden",
  "hidden [@media(max-resolution:1.99dppx)]:[@container(max-width:559.98px)]:inline [@container(max-width:279.98px)]:inline",
];

/** The base's shadows on the desk. */
const SHADOWS = (
  <>
    <path d={DECK.ground} filter="url(#laptop-far)" style={shade(1)} />
    <path d={DECK.contact} filter="url(#laptop-near)" style={shade(1)} />
  </>
);

/** The base, which never changes as the lid moves. */
const BASE = (
  <>
    <path d={DECK.hull} style={SURFACE} />
    <path d={DECK.hull} style={shade(SIDE)} />
    <path d={DECK.hinge} style={{ fill: HINGE }} />
    <path d={DECK.barrels} style={{ fill: BARREL }} />
    <path d={DECK.top} style={SURFACE} />
    {DECK.holes.map((holes, coarser) => (
      <path
        key={coarser}
        d={holes}
        className={HOLES_SHOWN[coarser]}
        strokeWidth={HOLE * 2 ** coarser}
        strokeLinecap="round"
        style={{ stroke: WELL, fill: "none" }}
      />
    ))}
    <path d={DECK.well} style={{ fill: WELL }} />
    <path d={DECK.keys} style={{ fill: KEY }} />
    <path d={DECK.touchId} style={{ fill: TOUCH_ID }} />
    <path d={DECK.touchIdRing} {...stroke} style={hairline(KEY)} />
    <path d={DECK.trackpad} style={shade(0.2)} />
    <path d={DECK.trackpad} {...stroke} style={hairline("var(--border)")} />
    <path d={DECK.scoop} style={shade(1)} />
    <path d={DECK.lines} {...stroke} style={hairline("var(--hairline)")} />
  </>
);

const DEFS = (
  <>
    <filter id="laptop-near" filterUnits="userSpaceOnUse" x="0" y="0" width="100" height="70">
      <feGaussianBlur stdDeviation="0.4 0.2" />
    </filter>
    <filter id="laptop-far" filterUnits="userSpaceOnUse" x="0" y="0" width="100" height="70">
      <feGaussianBlur stdDeviation="2 0.9" />
    </filter>
    <linearGradient id="laptop-sheen" x1="0" y1="0" x2="0.35" y2="1">
      <stop offset="0" style={{ stopColor: "color-mix(in srgb, var(--surface) 70%, var(--bg))" }} />
      <stop offset="1" style={{ stopColor: "var(--surface)" }} />
    </linearGradient>
  </>
);

type LaptopProps = {
  /** How far the lid has closed, from 0 (open) to 1 (shut on the base). */
  closed: number;
  /** How bright the display is, from 0 (off) to 1. */
  display: number;
  /** How much of its shadow the laptop casts on the desk, from 0 (carried) to 1. */
  grounded?: number;
  children: ReactNode;
};

/**
 * A MacBook seen from the front and a little above, with `children` on its
 * display: one SVG drawn from the laptop's projected outline, and the screen
 * on CSS 3D transforms that put it in the same place.
 */
export function Laptop({ closed, display, grounded = 1, children }: LaptopProps) {
  const lid = useMemo(() => lidArt(closed), [closed]);
  const pose = lidPose(closed);

  return (
    <>
      <svg viewBox="0 0 100 70" aria-hidden="true" className="absolute inset-0 size-full overflow-visible">
        <defs>
          {DEFS}
          {lid.shadow && (
            <linearGradient id="laptop-lid-shadow" gradientUnits="userSpaceOnUse" x1="0" x2="0" y1={lid.shadow.from} y2={lid.shadow.to}>
              <stop offset="0" style={{ stopColor: "var(--shadow)" }} />
              <stop offset="1" style={{ stopColor: "var(--shadow)", stopOpacity: 0 }} />
            </linearGradient>
          )}
          {/*
            A mask and not a clip path: the three shapes are painted one over the other, so which way round each
            outline runs does not matter. As two paths of one clip path the lid went missing for single frames of
            its swing, at the angles where the outline that clears it happened to run the other way.
          */}
          {lid.cut && (
            <mask id="laptop-lid-cut" maskUnits="userSpaceOnUse" x="-50" y="-50" width="200" height="170">
              <rect x="-50" y="-50" width="200" height="170" fill="white" />
              <path d={lid.cut.hidden} fill="black" />
              <path d={lid.cut.clear} fill="white" />
            </mask>
          )}
        </defs>
        <g opacity={fixed(grounded)}>{SHADOWS}</g>
        {BASE}
        {lid.shadow && <path d={DECK.top} fill="url(#laptop-lid-shadow)" opacity={fixed(closed)} />}
        <g mask={lid.cut ? "url(#laptop-lid-cut)" : undefined}>
          <path d={lid.hull} style={SURFACE} />
          <path d={lid.hull} style={shade(SIDE)} />
          {lid.facing ? (
            <>
              <path d={lid.face} style={{ fill: RIM_TONE }} />
              {lid.bezel && <path d={lid.bezel} fill="black" />}
            </>
          ) : (
            <path d={lid.face} fill="url(#laptop-sheen)" />
          )}
          <path d={lid.lines} {...stroke} style={hairline("var(--hairline)")} />
        </g>
      </svg>
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
          <div
            className="absolute left-0 [backface-visibility:hidden]"
            style={{
              top: cq(-DEPTH),
              width: cq(WIDTH),
              height: cq(DEPTH),
              transformOrigin: "bottom",
              transform: `translate3d(0, ${cq(pose.along)}, ${cq(LIFT + pose.up)}) rotateX(${fixed(pose.angle)}deg)`,
            }}
          >
            <div
              className="absolute overflow-hidden bg-[#0d0d0d] [container-type:inline-size]"
              style={{
                inset: `${cq(BEZEL)} ${cq(BEZEL)} ${cq(CHIN)}`,
                borderRadius: `${cq(ROUND - BEZEL)} ${cq(ROUND - BEZEL)} 0 0`,
              }}
            >
              <div className="h-full" style={{ opacity: fixed(display) }}>
                {children}
              </div>
              <div
                className="absolute inset-0"
                style={{ background: "linear-gradient(110deg, color-mix(in srgb, var(--hairline) 9%, transparent), transparent 35%)" }}
              />
              <div className="absolute left-1/2 top-0 flex h-[3.6%] w-[12.5%] -translate-x-1/2 items-center justify-center rounded-b-[0.8cqw] bg-black">
                <div className="size-[0.7cqw] rounded-full" style={{ background: LENS }} />
              </div>
            </div>
          </div>
        </div>
      </div>
    </>
  );
}
