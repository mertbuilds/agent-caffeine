"use client";

import { useLayoutEffect, useRef, useState, type CSSProperties } from "react";
import { PILL, SIZES } from "@/components/pill";
import { SupportCta } from "@/components/track";
import { REPO_URL, SUPPORT_URL } from "@/lib/site";
import { useLessMotion } from "@/lib/use-less-motion";
import { useSeen } from "@/lib/use-seen";

/** One part of the section after the one before it, in milliseconds, as they rise. */
const STAGGER = 80;

/** The dashes of a line `support-draw` draws, with its `pathLength` set to 1. */
const DRAWN_DASHES = "1 2";

/** The ink of the cup: the page's own muted line, its paper, and the one blue. */
const INK = {
  line: { fill: "none", stroke: "var(--muted)", strokeLinecap: "round", strokeLinejoin: "round" },
  paper: "var(--bg)",
  accent: "var(--accent)",
} as const;

const LINE = 1.2;
/** The heart the steam makes, in a 24 unit box, and where its box stands. */
const HEART = { scale: 1.8, x: 100 - 12 * 1.8, y: 20 };
/** A heart in a 24 unit box, as one line a pen can draw from its foot round to its foot. */
const HEART_LINE =
  "M12 21s-7.5-4.6-9.3-9.5C1.4 8 3.4 4.5 6.9 4.5c2 0 3.7 1 5.1 2.9 1.4-1.9 3.1-2.9 5.1-2.9 3.5 0 5.5 3.5 4.2 7C19.5 16.4 12 21 12 21Z";
/** The heart's two halves, each from its foot up round its lobe to the dip between the lobes, so a pen draws both at once. */
const HALVES = [
  "M12 21s-7.5-4.6-9.3-9.5C1.4 8 3.4 4.5 6.9 4.5c2 0 3.7 1 5.1 2.9",
  "M12 21s7.5-4.6 9.3-9.5C22.6 8 20.6 4.5 17.1 4.5c-2 0-3.7 1-5.1 2.9",
];
/** The three wisps, each from the cup up to the heart: its left side, its foot and its right side. */
const WISPS = [
  "M90 112C80 98 96 84 88 70S80 50 83.3 40.7",
  "M100 112C94 100 106 88 100 76S98 62 100 57.8",
  "M110 112C120 98 104 84 112 70S120 50 116.7 40.7",
];
/** When the wisps start to rise and each one after the one before, when the heart is drawn, and when it first beats, in milliseconds. */
const RISE = 300;
const WISP_NEXT = 150;
const HEART_AT = 1100;
const BEAT_AT = 2000;

const drawn = (play: boolean, ms: number, delay: number, easing: string) =>
  play ? { strokeDasharray: DRAWN_DASHES, animation: `support-draw ${ms}ms ${easing} ${delay}ms backwards` } : {};

/** A filled heart, as tall as the button's letters are set. */
function SmallHeart() {
  return (
    <svg aria-hidden="true" className="support-cta-heart size-3.5 shrink-0" viewBox="0 0 24 24" style={{ fill: INK.accent }}>
      <path d={HEART_LINE} />
    </svg>
  );
}

/**
 * The robot's head from the app's menu bar icon (components/menu-icon.tsx),
 * on its 21 by 20 canvas, as lines: antenna, ears, head and happy eyes. Drawn
 * at `scale` with its top left at `x`, `y`, and lines `width` wide.
 */
function RobotHead({ x, y, scale, width }: { x: number; y: number; scale: number; width: number }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${scale})`} {...INK.line} strokeWidth={width / scale}>
      <circle cx="10.5" cy="1.6" r="1.1" />
      <path d="M10.5 2.7V4.5" />
      <path d="M2.5 8.5H1.5A1.5 1.5 0 0 0 0 10V12A1.5 1.5 0 0 0 1.5 13.5H2.5" />
      <path d="M18.5 8.5H19.5A1.5 1.5 0 0 1 21 10V12A1.5 1.5 0 0 1 19.5 13.5H18.5" />
      <rect height="13" rx="5.5" width="16" x="2.5" y="4.5" style={{ fill: INK.paper }} />
      <path d="M6 12Q7.5 8.6 9 12M12 12Q13.5 8.6 15 12" />
    </g>
  );
}

/**
 * A line-art coffee cup on its saucer, with the robot's head on its front.
 * Its steam rises in three wisps that join into a heart outline. `play` draws
 * the wisps up out of the cup one after another, then the heart from its foot,
 * and the heart beats softly once in a while from then on.
 */
function Cup({ play }: { play: boolean }) {
  return (
    <svg
      aria-label="A coffee cup with the Agent Caffeine robot on it. Its steam rises into a blue heart"
      className="block h-auto w-full overflow-visible"
      role="img"
      viewBox="0 0 200 196"
    >
      <g {...INK.line} strokeWidth={LINE}>
        <ellipse cx="100" cy="180" rx="58" ry="8" />
        <path d="M137 132C156 130 156 160 132 162" />
        <path d="M62 122C62 150 70 172 84 176H116C130 172 138 150 138 122" style={{ fill: INK.paper }} />
        <ellipse cx="100" cy="122" rx="38" ry="7" style={{ fill: INK.paper }} />
        <ellipse cx="100" cy="124" rx="31" ry="4.2" style={{ stroke: "var(--border)" }} />
        {WISPS.map((d, index) => (
          <path d={d} key={d} opacity={0.6} pathLength={1} style={drawn(play, 900, RISE + index * WISP_NEXT, "var(--ease-smooth-out)")} />
        ))}
      </g>
      <RobotHead scale={1.3} width={LINE} x={100 - 10.5 * 1.3} y={132} />
      <g transform={`translate(${HEART.x} ${HEART.y}) scale(${HEART.scale})`}>
        <g
          style={{
            transformBox: "fill-box",
            transformOrigin: "center",
            animation: play ? `support-soft-beat 4.5s ease-in-out ${BEAT_AT}ms infinite` : undefined,
          }}
        >
          {HALVES.map((d) => (
            <path
              d={d}
              fill="none"
              key={d}
              pathLength={1}
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={LINE / HEART.scale}
              style={{ stroke: INK.accent, ...drawn(play, 700, HEART_AT, "ease-in-out") }}
            />
          ))}
        </g>
      </g>
    </svg>
  );
}

/**
 * The closing ask of the home page: the title with its one blue word, two
 * short muted lines, the button with its heart, and the cup to the right
 * (above the words on a phone). `/support`, where the app and old links
 * point, redirects here.
 *
 * The server draws it finished. Still under the window once the page has come
 * alive, its parts hide and rise one after another as it comes into view, and
 * the cup plays. Off screen it goes back to waiting, so it plays again.
 */
export function Support() {
  const section = useRef<HTMLElement>(null);
  const lessMotion = useLessMotion();
  const seen = useSeen(section, 0.3);
  const [below, setBelow] = useState(false);

  // Only a section wholly under the window is hidden, where nobody sees it go.
  useLayoutEffect(() => {
    const top = section.current?.getBoundingClientRect().top;
    setBelow(top !== undefined && top > window.innerHeight);
  }, []);

  const moving = below && !lessMotion;
  const part = (place: number): { className: string; style?: CSSProperties } => {
    if (!moving) return { className: "" };
    if (!seen) return { className: "support-hidden" };
    return { className: "support-rise", style: { animationDelay: `${place * STAGGER}ms` } };
  };
  const at = (place: number, className: string) => {
    const motion = part(place);
    return { className: `${className} ${motion.className}`, style: motion.style };
  };

  return (
    <section
      id="support"
      ref={section}
      className="support mx-auto grid w-full max-w-[880px] scroll-mt-20 grid-cols-[minmax(0,1fr)] items-start gap-y-10 md:grid-cols-[minmax(0,1fr)_auto] md:gap-x-12"
    >
      <div className="flex flex-col items-start gap-3">
        <h2 {...at(0, "mb-2 text-balance text-[2.5rem] font-medium leading-[1.05] tracking-[-0.02em] md:text-5xl")}>
          <span className="text-accent">Support</span> Agent Caffeine
        </h2>
        <p {...at(1, "max-w-[48ch] text-pretty leading-relaxed text-muted")}>
          Agent Caffeine is free and open source. If it helps you, you can support the work. You choose the amount.
        </p>
        <p {...at(2, "max-w-[48ch] text-pretty leading-relaxed text-muted")}>
          Support is a gift. It unlocks nothing, and the app is the same for everyone.
        </p>
        {SUPPORT_URL === null ? (
          <div {...at(3, "mt-2 flex flex-col gap-3 text-pretty leading-relaxed")}>
            <p>Support is not set up yet.</p>
            <p>
              <a href={REPO_URL}>The source code is on GitHub</a>
            </p>
          </div>
        ) : (
          <div {...at(3, "mt-2 flex flex-col items-start gap-4")}>
            <SupportCta href={SUPPORT_URL} placement="section" className={`support-cta ${PILL} bg-fg text-bg ${SIZES.large}`}>
              <span className="flex items-center gap-2">
                <SmallHeart />
                Support the project
              </span>
            </SupportCta>
            <p className="max-w-[48ch] text-pretty text-sm text-muted">
              GitHub Sponsors handles it: one-time or monthly, any amount. <a href={REPO_URL}>The source code is on GitHub</a>
            </p>
          </div>
        )}
      </div>
      <div {...at(1, "order-first w-[min(80%,300px)] justify-self-center md:order-none md:w-[240px] md:justify-self-auto")}>
        <Cup play={moving && seen} />
      </div>
    </section>
  );
}
