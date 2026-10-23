import { create, props } from '@stylexjs/stylex';
import { memo, useMemo, type CSSProperties } from 'react';
import { BEZEL, CHIN, DEPTH, HOLE, LIFT, ROUND, WIDTH, fixed, type View } from './geometry.ts';

const cq = (size: number) => `${fixed(size)}cqw`;

// Anodised aluminium in close tones, lit from above: the tops are the page's
// surface, the sides a step darker under the page's shadow, the rim round the
// glass a step towards the border, and the shut lid an even tone. The glass,
// the hinge cover and the keyboard are near black, as on the machine, and the
// hinge's barrels a darker aluminium in the shade of the lid.
const SURFACE: CSSProperties = { fill: 'var(--surface)' };
const shade = (share: number): CSSProperties => ({ fill: 'var(--shadow)', fillOpacity: share });
const SIDE = 0.45;
const RIM_TONE = 'color-mix(in srgb, var(--surface) 60%, var(--border))';
const LENS = 'color-mix(in srgb, var(--hairline) 15%, black)';
const HINGE = 'color-mix(in srgb, var(--hairline) 6%, black)';
const BARREL = 'color-mix(in srgb, var(--surface) 78%, black)';
const WELL = 'color-mix(in srgb, var(--surface) 10%, black)';
const KEY = `color-mix(in srgb, var(--hairline) 22%, ${WELL})`;
const TOUCH_ID = `color-mix(in srgb, var(--hairline) 12%, ${WELL})`;

const hairline = (color: string): CSSProperties => ({ fill: 'none', stroke: color });
const stroke = {
  strokeLinecap: 'round',
  strokeLinejoin: 'round',
  strokeWidth: 1,
  vectorEffect: 'non-scaling-stroke',
} as const;

// Which field of holes shows: the full one where a hole is about a device
// pixel (a scene 560px wide at two pixels a px), the half one down to half
// that, the quarter one below.
const FINE = '@media (min-resolution: 2dppx)';
const COARSE = '@media (max-resolution: 1.99dppx)';
const WIDE = '@container (min-width: 560px)';
const NARROW = '@container (max-width: 559.98px)';
const TINY = '@container (max-width: 279.98px)';

const styles = create({
  art: {
    height: '100%',
    inset: 0,
    overflow: 'visible',
    position: 'absolute',
    width: '100%',
  },
  glass: {
    backgroundColor: '#0d0d0d',
    containerType: 'inline-size',
    overflow: 'hidden',
    position: 'absolute',
  },
  holesFull: {
    display: { default: 'none', [FINE]: { default: null, [WIDE]: 'inline' } },
  },
  holesHalf: {
    display: {
      [COARSE]: { default: null, [NARROW]: 'none' },
      default: null,
      [FINE]: { default: null, [WIDE]: 'none' },
      [TINY]: 'none',
    },
  },
  holesQuarter: {
    display: {
      [COARSE]: { default: null, [NARROW]: 'inline' },
      default: 'none',
      [TINY]: 'inline',
    },
  },
  lens: {
    borderRadius: '9999px',
    height: '0.7cqw',
    width: '0.7cqw',
  },
  lid: {
    backfaceVisibility: 'hidden',
    left: 0,
    position: 'absolute',
  },
  notch: {
    alignItems: 'center',
    backgroundColor: 'black',
    borderBottomLeftRadius: '0.8cqw',
    borderBottomRightRadius: '0.8cqw',
    display: 'flex',
    height: '3.6%',
    justifyContent: 'center',
    left: '50%',
    position: 'absolute',
    top: 0,
    transform: 'translateX(-50%)',
    width: '12.5%',
  },
  sheen: {
    inset: 0,
    position: 'absolute',
  },
  slab: {
    position: 'absolute',
    transformStyle: 'preserve-3d',
  },
  stage: {
    left: '50%',
    position: 'absolute',
    transformStyle: 'preserve-3d',
  },
});

const HOLES_SHOWN = [styles.holesFull, styles.holesHalf, styles.holesQuarter];

/** The base, which never changes as the lid moves. */
const Base = memo(function Base({ view: { DECK, id } }: { view: View }) {
  return (
    <>
      <path d={DECK.ground} filter={`url(#laptop-${id}-far)`} style={shade(1)} />
      <path d={DECK.contact} filter={`url(#laptop-${id}-near)`} style={shade(1)} />
      <path d={DECK.hull} style={SURFACE} />
      <path d={DECK.hull} style={shade(SIDE)} />
      <path d={DECK.hinge} style={{ fill: HINGE }} />
      <path d={DECK.barrels} style={{ fill: BARREL }} />
      <path d={DECK.top} style={SURFACE} />
      {DECK.holes.map((holes, coarser) => (
        <path
          d={holes}
          key={coarser}
          {...props(HOLES_SHOWN[coarser])}
          strokeLinecap="round"
          strokeWidth={HOLE * 2 ** coarser}
          style={{ fill: 'none', stroke: WELL }}
        />
      ))}
      <path d={DECK.well} style={{ fill: WELL }} />
      <path d={DECK.keys} style={{ fill: KEY }} />
      <path d={DECK.touchId} style={{ fill: TOUCH_ID }} />
      <path d={DECK.touchIdRing} {...stroke} style={hairline(KEY)} />
      <path d={DECK.trackpad} style={shade(0.2)} />
      <path d={DECK.trackpad} {...stroke} style={hairline('var(--border)')} />
      <path d={DECK.scoop} style={shade(1)} />
      <path d={DECK.lines} {...stroke} style={hairline('var(--hairline)')} />
    </>
  );
});

/** What the drawing of one view refers to. Each view has its own names, since both are in the page. */
const defs = (id: string) => (
  <>
    <filter
      filterUnits="userSpaceOnUse"
      height="70"
      id={`laptop-${id}-near`}
      width="100"
      x="0"
      y="0"
    >
      <feGaussianBlur stdDeviation="0.4 0.2" />
    </filter>
    <filter
      filterUnits="userSpaceOnUse"
      height="70"
      id={`laptop-${id}-far`}
      width="100"
      x="0"
      y="0"
    >
      <feGaussianBlur stdDeviation="2 0.9" />
    </filter>
    <linearGradient id={`laptop-${id}-sheen`} x1="0" x2="0.35" y1="0" y2="1">
      <stop offset="0" style={{ stopColor: 'color-mix(in srgb, var(--surface) 70%, var(--bg))' }} />
      <stop offset="1" style={{ stopColor: 'var(--surface)' }} />
    </linearGradient>
  </>
);

type LaptopProps = {
  /** How far the lid has closed, from 0 (open) to 1 (shut on the base). */
  closed: number;
  /** The eye that sees it. */
  view: View;
};

/**
 * A MacBook seen from the front and a little above, its display dark: one SVG
 * drawn from the laptop's projected outline, and the glass on CSS 3D
 * transforms that put it in the same place.
 */
export const Laptop = memo(function Laptop({ closed, view }: LaptopProps) {
  const { DECK, id } = view;
  const lid = useMemo(() => view.lidArt(closed), [view, closed]);
  const pose = view.lidPose(closed);

  return (
    <>
      <svg aria-hidden="true" viewBox={`0 0 100 ${view.height}`} {...props(styles.art)}>
        <defs>
          {defs(id)}
          {lid.shadow && (
            <linearGradient
              gradientUnits="userSpaceOnUse"
              id={`laptop-${id}-lid-shadow`}
              x1="0"
              x2="0"
              y1={lid.shadow.from}
              y2={lid.shadow.to}
            >
              <stop offset="0" style={{ stopColor: 'var(--shadow)' }} />
              <stop offset="1" style={{ stopColor: 'var(--shadow)', stopOpacity: 0 }} />
            </linearGradient>
          )}
          {/*
            A mask and not a clip path: the three shapes are painted one over the other, so which way round each
            outline runs does not matter. As two paths of one clip path the lid went missing for single frames of
            its swing, at the angles where the outline that clears it happened to run the other way.
          */}
          {lid.cut && (
            <mask
              height="170"
              id={`laptop-${id}-lid-cut`}
              maskUnits="userSpaceOnUse"
              width="200"
              x="-50"
              y="-50"
            >
              <rect fill="white" height="170" width="200" x="-50" y="-50" />
              <path d={lid.cut.hidden} fill="black" />
              <path d={lid.cut.clear} fill="white" />
            </mask>
          )}
        </defs>
        <Base view={view} />
        {lid.shadow && (
          <path d={DECK.top} fill={`url(#laptop-${id}-lid-shadow)`} opacity={fixed(closed)} />
        )}
        <g mask={lid.cut ? `url(#laptop-${id}-lid-cut)` : undefined}>
          <path d={lid.hull} style={SURFACE} />
          <path d={lid.hull} style={shade(SIDE)} />
          {lid.facing ? (
            <>
              <path d={lid.face} style={{ fill: RIM_TONE }} />
              {lid.bezel && <path d={lid.bezel} fill="black" />}
            </>
          ) : (
            <path d={lid.face} fill={`url(#laptop-${id}-sheen)`} />
          )}
          <path d={lid.lines} {...stroke} style={hairline('var(--hairline)')} />
        </g>
      </svg>
      <div
        {...props(styles.stage)}
        style={{
          top: cq(view.ANCHOR),
          transform: `translateZ(${cq(-view.BACK)}) rotateX(${view.CAMERA}deg)`,
        }}
      >
        <div
          {...props(styles.slab)}
          style={{
            height: cq(DEPTH),
            left: cq(-WIDTH / 2),
            top: cq(-DEPTH / 2),
            transform: 'rotateX(90deg)',
            width: cq(WIDTH),
          }}
        >
          <div
            {...props(styles.lid)}
            style={{
              height: cq(DEPTH),
              top: cq(-DEPTH),
              transform: `translate3d(0, ${cq(pose.along)}, ${cq(LIFT + pose.up)}) rotateX(${fixed(pose.angle)}deg)`,
              transformOrigin: 'bottom',
              width: cq(WIDTH),
            }}
          >
            <div
              {...props(styles.glass)}
              style={{
                borderRadius: `${cq(ROUND - BEZEL)} ${cq(ROUND - BEZEL)} 0 0`,
                inset: `${cq(BEZEL)} ${cq(BEZEL)} ${cq(CHIN)}`,
              }}
            >
              <div
                {...props(styles.sheen)}
                style={{
                  background:
                    'linear-gradient(110deg, color-mix(in srgb, var(--hairline) 9%, transparent), transparent 35%)',
                }}
              />
              <div {...props(styles.notch)}>
                <div {...props(styles.lens)} style={{ background: LENS }} />
              </div>
            </div>
          </div>
        </div>
      </div>
    </>
  );
});
