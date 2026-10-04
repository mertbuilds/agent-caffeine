import { useId, type ReactNode } from "react";
import { stretch } from "@/lib/playhead";

/** Every drawing's box, 4:3. */
export const WIDTH = 240;
export const HEIGHT = 180;

/**
 * A 4:3 crop of the drawings' box as a viewBox, `width` wide and centred
 * across, standing so the line `y` falls `share` of its height from its top.
 */
export function crop(width: number, y: number, share = 0): string {
  const height = (width * HEIGHT) / WIDTH;
  return `${(WIDTH - width) / 2} ${y - share * height} ${width} ${height}`;
}

/** Thin lines in the muted colour that stay one pixel wide however large the drawing is. */
export const HAIRLINE = {
  fill: "none",
  stroke: "var(--hairline)",
  strokeLinecap: "round",
  strokeLinejoin: "round",
  strokeWidth: 1,
  vectorEffect: "non-scaling-stroke",
} as const;

/** Where the lid meets the base, the line the lid folds down about. */
const HINGE = 128;
const LID = { height: 78, radius: 5, width: 120, x: 60 };
/** How thick the lid stands once it has folded down onto the base. */
const SLAB = 3;
/** Where the lid's top stands once it has folded down onto the base. */
export const CLOSED_TOP = HINGE - SLAB;
/** Where the base, and so the laptop, ends at the bottom. */
export const BASE_BOTTOM = 133;
/** The display, a bezel inside the lid, where `children` are drawn. */
export const SCREEN = { height: 70, radius: 1, width: 112, x: 64, y: 54 };
/** The slab the lid stands on, a little wider than the lid, with the notch a thumb opens it by. */
const BASE =
  `M48 128 H192 V130.5 Q192 ${BASE_BOTTOM} 189.5 ${BASE_BOTTOM} H50.5 Q48 ${BASE_BOTTOM} 48 130.5 Z M112 128 Q112 130 114 130 H126 Q128 130 128 128`;

/**
 * A laptop seen from the front. As `closed` goes from 0 to 1 the lid folds
 * down about the hinge onto the base, and what is on its display folds and
 * fades with it. `children` are drawn from the display's top left corner.
 */
export function Laptop({ children, closed }: { children?: ReactNode; closed: number }) {
  const lid = LID.height + (SLAB - LID.height) * closed;
  const fold = lid / LID.height;
  const screenTop = HINGE - (HINGE - SCREEN.y) * fold;
  return (
    <>
      <path d={BASE} {...HAIRLINE} fill="var(--bg)" />
      <rect
        height={lid}
        rx={Math.min(LID.radius, lid / 2)}
        width={LID.width}
        x={LID.x}
        y={HINGE - lid}
        {...HAIRLINE}
        fill="var(--bg)"
      />
      <rect
        height={SCREEN.height * fold}
        opacity={0.5 * (1 - stretch(closed, 0.5, 1))}
        rx={SCREEN.radius}
        width={SCREEN.width}
        x={SCREEN.x}
        y={screenTop}
        {...HAIRLINE}
      />
      <g
        opacity={1 - stretch(closed, 0, 0.5)}
        transform={`translate(${SCREEN.x} ${screenTop}) scale(1 ${fold})`}
      >
        {children}
      </g>
    </>
  );
}

/**
 * A floating copy of the display, `y` from the top of the box, shown as far
 * as `shown` and its dashed outline as far as `outline`. `children` are drawn
 * as on the display.
 */
export function Panel({
  children,
  outline,
  shown,
  y,
}: {
  children?: ReactNode;
  outline: number;
  shown: number;
  y: number;
}) {
  return (
    <g opacity={shown}>
      <rect
        fill="var(--bg)"
        height={SCREEN.height}
        rx={3}
        width={SCREEN.width}
        x={SCREEN.x}
        y={y}
      />
      <rect
        height={SCREEN.height}
        opacity={outline}
        rx={3}
        strokeDasharray="3 2"
        width={SCREEN.width}
        x={SCREEN.x}
        y={y}
        {...HAIRLINE}
      />
      <g transform={`translate(${SCREEN.x} ${y})`}>{children}</g>
    </g>
  );
}

const CUP_BODY = "M1 1.5 H8 V4.5 Q8 7.5 4.5 7.5 Q1 7.5 1 4.5 Z";
const CUP_HANDLE = "M8 2.5 H9 Q10.5 2.5 10.5 4 Q10.5 5.5 9 5.5 H8";
/** How wide the cup stands on its saucer, and how far down from its top the saucer is. */
export const CUP_SIZE = { saucer: 9.5, width: 11 };
const SAUCER = `M0 ${CUP_SIZE.saucer} H${CUP_SIZE.width}`;

/**
 * The menu bar cup, a cup on its saucer from its top left corner: an outline when `full` is 0, filled with the accent when 1.
 */
export function Cup({ full }: { full: number }) {
  const clip = `cup-${useId().replace(/[^a-zA-Z0-9]/g, "")}`;
  const level = 6 * full;
  return (
    <>
      <clipPath id={clip}>
        <path d={CUP_BODY} />
      </clipPath>
      <rect
        clipPath={`url(#${clip})`}
        fill="var(--accent)"
        height={level}
        width={7}
        x={1}
        y={7.5 - level}
      />
      <g opacity={1 - full}>
        <path d={CUP_BODY} {...HAIRLINE} />
        <path d={CUP_HANDLE} {...HAIRLINE} />
        <path d={SAUCER} {...HAIRLINE} />
      </g>
      <g opacity={full}>
        <path d={CUP_BODY} {...HAIRLINE} stroke="var(--accent)" />
        <path d={CUP_HANDLE} {...HAIRLINE} stroke="var(--accent)" />
        <path d={SAUCER} {...HAIRLINE} stroke="var(--accent)" />
      </g>
    </>
  );
}

/** The lines of work, in the display's units: where the first sits, how far apart, how long each is. */
const LINES = { bar: 3, gap: 8, left: 8, prompt: 16, top: 19 };
const LENGTHS = [44, 78, 58, 84, 40, 66];

/** Where a line starts: the first after its prompt mark, the rest at the margin. */
function lineStart(index: number): number {
  return index === 0 ? LINES.prompt : LINES.left;
}

/** How much of line `index` is in once `shown` lines are. */
function grownOf(shown: number, index: number): number {
  return Math.min(1, Math.max(0, shown - index));
}

/**
 * Terminal lines of agent work, `shown` of them in, a fractional `shown`
 * growing the last one. A small accent dot pulses at the end of the newest
 * line as far as `live`, and a check mark comes in after it as far as `done`.
 */
export function WorkLines({
  done = 0,
  live = 0,
  shown,
}: {
  done?: number;
  live?: number;
  shown: number;
}) {
  const newest = Math.max(0, Math.ceil(shown) - 1);
  const tipX = lineStart(newest) + LENGTHS[newest] * grownOf(shown, newest) + 4;
  const tipY = LINES.top + newest * LINES.gap + LINES.bar / 2;
  return (
    <>
      <path
        d={`M${LINES.left} ${LINES.top - 0.5} L${LINES.left + 3} ${LINES.top + 1.5} L${LINES.left} ${LINES.top + 3.5}`}
        opacity={Math.min(1, shown * 3)}
        {...HAIRLINE}
      />
      {LENGTHS.map((length, index) => {
        const grown = grownOf(shown, index);
        if (grown <= 0) {
          return null;
        }
        const width = length * grown;
        return (
          <rect
            key={index}
            fill="var(--hairline)"
            fillOpacity={0.5}
            height={LINES.bar}
            opacity={Math.min(1, grown * 4)}
            rx={Math.min(LINES.bar / 2, width / 2)}
            width={width}
            x={lineStart(index)}
            y={LINES.top + index * LINES.gap}
          />
        );
      })}
      {live > 0 ? (
        <g opacity={live}>
          <circle className="drawing-pulse" cx={tipX} cy={tipY} fill="var(--accent)" r={1.6} />
        </g>
      ) : null}
      {done > 0 ? (
        <path
          d="M-2.5 0 L-0.8 1.8 L2.5 -1.8"
          opacity={done}
          transform={`translate(${tipX + 0.5} ${tipY}) scale(${0.6 + 0.4 * done})`}
          {...HAIRLINE}
          stroke="var(--accent)"
          strokeWidth={1.5}
        />
      ) : null}
    </>
  );
}

/** Where the menu bar puts its cup on the display, and how small. */
export const MENU_CUP = { scale: 0.8, x: SCREEN.width - 14, y: 1.5 };

/** The display's menu bar strip, and the cup in it when there is one. */
export function MenuBar({ cup }: { cup?: number | undefined }) {
  return (
    <>
      <path d={`M0 11 H${SCREEN.width}`} opacity={0.5} {...HAIRLINE} />
      {cup === undefined ? null : (
        <g transform={`translate(${MENU_CUP.x} ${MENU_CUP.y}) scale(${MENU_CUP.scale})`}>
          <Cup full={cup} />
        </g>
      )}
    </>
  );
}

/** A small moon and two z's for a Mac that has gone to sleep, from its centre, as far as `shown`. */
export function Sleep({ shown }: { shown: number }) {
  return (
    <g opacity={shown} transform={`translate(0 ${3 * (1 - shown)})`}>
      <path d="M1.5 -5.3 A5.5 5.5 0 1 0 5.4 1.2 A4.4 4.4 0 0 1 1.5 -5.3 Z" {...HAIRLINE} />
      <path d="M8 -7 H11 L8 -4 H11" {...HAIRLINE} />
      <path d="M12.5 -12 H14.5 L12.5 -10 H14.5" {...HAIRLINE} />
    </g>
  );
}

/** A short line of words under the laptop, in the page's font, rising in as far as `shown`. */
export function Label({ children, color, shown }: { children: string; color: string; shown: number }) {
  return (
    <text
      fill={color}
      fontSize={6}
      fontWeight={500}
      opacity={shown}
      textAnchor="middle"
      x={WIDTH / 2}
      y={148 + 3 * (1 - shown)}
    >
      {children}
    </text>
  );
}
