"use client";

import { easeInOut } from "motion/react";
import { useMotionValueEvent } from "motion/react";
import { memo, useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { AgentIcon, type AgentIconName } from "@/components/agent-icons";
import { Flow, PanelSurface } from "@/components/agents-panel";
import { DESK, PHONE, fixed } from "@/components/laptop/geometry";
import { Laptop } from "@/components/laptop/laptop";
import { MenuIcon } from "@/components/menu-icon";
import { Robot } from "@/components/robot";
import { heroScene } from "@/lib/motion";
import { stretch, useLoop } from "@/lib/playhead";
import { ICON_AT_REST, RELEASE_AFTER, detailOf, headlineText, iconLook, pose, type Headline } from "@/lib/simulator";
import { useLessMotion } from "@/lib/use-less-motion";
import { useSeen } from "@/lib/use-seen";
import { useTabHidden } from "@/lib/use-tab-hidden";

const MUTED = "text-[var(--panel-muted)]";
const GREEN = "light-dark(#28a745, #32d74b)";

/** The time on the menu bar when the lid closes, in minutes of the day. */
const CLOCK_START = 14 * 60 + 2;
/**
 * The glass of the open display in the scene, in hundredths of the scene's
 * width (`lidArt(0)` less the bezel and the chin). The open lid faces the eye,
 * so the glass is a plain rectangle, and the flat menu lies on it. Both views
 * have the open lid in the same place, so this is the glass of both.
 */
const GLASS = { left: 23.07, top: 6.21, width: 53.86, height: 35, round: 0.87 };
/**
 * The laptop as each size of the page sees it. On a phone the scene is wider than the page, as much as the
 * laptop's widest part (59.34 hundredths of the scene) fits between the page's gutters, and less tall.
 */
const VIEWS = [
  { view: PHONE, shown: "sm:hidden" },
  { view: DESK, shown: "hidden sm:block" },
] as const;
/**
 * The scene's width at which the menu is drawn at its own size (`--full`): 705 pixels for the menu with the
 * app's measures, and 520 on a phone, where a tighter cut of the menu keeps its words large enough to read.
 */
const SCALE =
  "scale-[calc(485/520)] [--full:520px] min-[375px]:scale-[calc(578/520)] min-[390px]:scale-[calc(603/520)] min-[430px]:scale-[calc(670/520)] sm:scale-[calc(810/705)] sm:[--full:705px] lg:scale-[calc(630/705)] xl:scale-[calc(810/705)]";
/** The gap between the glass's edge and the menu bar, in pixels at full size. */
const GAP = 3;

/** Seconds the check takes to come in. */
const CHECK_IN = 0.35;
/** The Mac's desktop, and how much of itself it keeps in the outline of the display once the lid is closed. */
const DESKTOP = "bg-[radial-gradient(130%_100%_at_50%_100%,#3b82f0,#12306e_65%,#0a1c44)]";
const DESKTOP_KEPT = 0.45;
/** Seconds the robot's tile takes to lose its colour, and the icon in the menu bar to go pale, once the Mac can sleep. */
const TONE_DOWN = 0.8;
/** How much of themselves the desktop and the outline keep once the Mac sleeps, and the menu, which has to stay readable. */
const ASLEEP = 0.45;
const MENU_ASLEEP = 0.75;
/** The moment of the loop that stands for all of it, for a reader who asked for less motion: the lid is closed, two agents work and one has just finished. */
const STILL = 3.38;

/** The agents at work, the longest first as the app lists them. `before` is the minutes each has worked when the lid closes, and `done` the minutes after that when it finishes. */
const AGENTS: readonly { icon: AgentIconName; name: string; folder: string; before: number; done: number }[] = [
  { icon: "claudecode", name: "Claude Code", folder: "wiki", before: 11, done: 27 },
  { icon: "codex", name: "Codex", folder: "api", before: 8, done: 18 },
  { icon: "cursor", name: "Cursor", folder: "website", before: 5, done: 9 },
];
const LAST_DONE = AGENTS[0];

/** The minutes that have passed since the lid closed, at `time` seconds into the loop. */
function minutesAt(time: number): number {
  const marks = heroScene.clock;
  for (let next = 1; next < marks.length; next += 1) {
    const [from, start] = marks[next - 1];
    const [to, end] = marks[next];
    if (time < to) {
      return start + (end - start) * Math.max(0, (time - from) / (to - from));
    }
  }
  return marks[marks.length - 1][1];
}

/** The second of the loop at which `minutes` have passed. */
function secondAt(minutes: number): number {
  return heroScene.clock.find((mark) => mark[1] >= minutes)?.[0] ?? heroScene.loop;
}

/**
 * What the app decides `minutes` after the lid closed, in the default mode
 * (`HoldPolicy.decide`): it keeps the Mac awake while an agent works and for
 * `RELEASE_AFTER` after the last one finished, and then the Mac can sleep.
 */
function headlineAt(minutes: number): Headline {
  const working = AGENTS.filter((agent) => minutes < agent.done);
  if (working.length > 0) {
    return { kind: "working", subject: working.length === 1 ? { one: working[0].name } : { many: working.length } };
  }
  return (minutes - LAST_DONE.done) * 60 < RELEASE_AFTER
    ? { kind: "finishedRecently", subject: { one: LAST_DONE.name } }
    : { kind: "idle", subject: { many: AGENTS.length } };
}

/** The second of the loop at which the Mac can sleep. */
const ASLEEP_AT = secondAt(LAST_DONE.done + RELEASE_AFTER / 60);

function clock(minutes: number): string {
  return `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, "0")}`;
}

/**
 * What moves without a step is written by the playhead straight into the
 * style of the few elements it belongs to, each marked with `data-hero`: so a
 * frame of the loop changes a few numbers and draws no component again, and
 * no other element has its style worked out again. `closed` is how far the
 * lid has closed, `dimmed` how far the sleeping Mac has dimmed, `rest` how
 * far the robot and the icon have gone pale, and `checks` how far each
 * agent's check has come in.
 */
type Frame = { closed: number; dimmed: number; rest: number; checks: readonly number[] };

const AT_START: Frame = { closed: 0, dimmed: 0, rest: 0, checks: AGENTS.map(() => 0) };

const STYLES: Record<string, (frame: Frame, place: number) => Record<string, string>> = {
  desktop: ({ closed, dimmed }) => ({ opacity: String(cut4((1 - (1 - DESKTOP_KEPT) * closed) * (1 - (1 - ASLEEP) * dimmed))) }),
  outline: ({ closed, dimmed }) => ({ opacity: String(cut4(closed * (1 - (1 - ASLEEP) * dimmed))) }),
  menu: ({ dimmed }) => ({ opacity: String(cut4(1 - (1 - MENU_ASLEEP) * dimmed)) }),
  icon: ({ rest }) => ({ opacity: String(cut4(1 - (1 - ICON_AT_REST) * rest)) }),
  // The robot takes its tone from this number (`rest` of `Robot`), and it reaches no other element.
  robot: ({ rest }) => ({ "--rest": String(rest) }),
  check: ({ checks }, place) => ({ opacity: String(checks[place]), transform: `scale(${cut4(0.6 + 0.4 * checks[place])})` }),
};

/** The spans of the loop where something moves without a step: the lid, each check as it comes in, the robot going pale, and the dim. Between them the playhead only counts minutes. */
const MOVING = [
  heroScene.close,
  ...AGENTS.map((agent) => [secondAt(agent.done), secondAt(agent.done) + CHECK_IN] as const).reverse(),
  [ASLEEP_AT, ASLEEP_AT + TONE_DOWN] as const,
  heroScene.dim,
] as const;

type Target = { element: HTMLElement; name: string; place: number; last: Record<string, string> };

/** The marked elements under `root`, to write frames into. */
function targets(root: HTMLElement): Target[] {
  return Array.from(root.querySelectorAll<HTMLElement>("[data-hero]"), (element) => {
    const [name, place] = (element.dataset.hero ?? "").split("-");
    return { element, name, place: Number(place ?? 0), last: {} };
  });
}

/** Writes a frame into the marked elements: only what differs from what was written there last. */
function paint(marked: readonly Target[], frame: Frame) {
  for (const target of marked) {
    for (const [property, value] of Object.entries(STYLES[target.name](frame, target.place))) {
      if (target.last[property] !== value) {
        target.last[property] = value;
        target.element.style.setProperty(property, value);
      }
    }
  }
}

function cut4(value: number) {
  return Math.round(value * 1e4) / 1e4;
}

/** An agent's mark in the slot of its ring, as in the app's menu: the arc goes round while it works, and an idle agent's mark is pale and has no ring. The arc is the `ring-turn` of globals.css, which costs no frame. */
function Mark({ icon, working }: { icon: AgentIconName; working: boolean }) {
  return (
    <span className="relative flex size-[30px] shrink-0 items-center justify-center sm:size-[34px]">
      <span
        className={`flex size-6 items-center justify-center rounded-[7px] bg-[color-mix(in_srgb,var(--panel-fg)_8%,transparent)] sm:size-7 sm:rounded-lg ${working ? "" : "opacity-55"}`}
      >
        <AgentIcon className="size-4 sm:size-[18px]" name={icon} />
      </span>
      {working && <span aria-hidden="true" className="ring-turn" />}
    </span>
  );
}

/** The check of the agent at `place` in the list, which comes in once it has finished. */
function Check({ place }: { place: number }) {
  return (
    <span aria-hidden="true" className="flex size-4 shrink-0 items-center justify-center rounded-full" data-hero={`check-${place}`} style={{ background: GREEN }}>
      <svg className="size-2 text-white" fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.8" viewBox="0 0 10 8">
        <path d="M1 4.2 3.8 7 9 1" />
      </svg>
    </span>
  );
}

/**
 * The Mac's menu bar along the top of the display: the Apple mark, Wi-Fi, the battery, our icon with its menu open, and the clock,
 * `minute` minutes after the lid closed. Its corners are the display's, less the gap round it. With `still` a number that changes does not roll.
 */
const MenuBar = memo(function MenuBar({ minute, still }: { minute: number; still: boolean }) {
  const stance = pose(headlineAt(minute));
  return (
    <div className="flex h-5 w-full items-center gap-3 rounded-[4px] sm:h-6 bg-[color-mix(in_srgb,var(--surface)_88%,transparent)] pl-2.5 pr-2 text-[13px] text-fg backdrop-blur">
      <svg className="h-[0.95em] w-auto shrink-0 -translate-y-px" fill="currentColor" viewBox="0 0 814 1000">
        <path d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.6-57-155.5-127C46.7 790.7 0 663 0 541.8c0-194.4 126.4-297.5 250.8-297.5 66.1 0 121.2 43.4 162.7 43.4 39.5 0 101.1-46 176.3-46 28.5 0 130.9 2.6 198.3 99.2zm-234-181.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8 1.3 15.6 1.9 18.1 3.2.6 8.4 1.3 13.6 1.3 45.4 0 102.5-30.4 135.5-71.3z" />
      </svg>
      <span className="flex-1" />
      <svg className="h-3 w-[17px] shrink-0" fill="none" stroke="currentColor" strokeLinecap="round" strokeWidth="1.7" viewBox="0 0 17 12">
        <path d="M1.2 4.4a10.4 10.4 0 0 1 14.6 0M3.9 7.1a6.6 6.6 0 0 1 9.2 0" />
        <circle cx="8.5" cy="10" fill="currentColor" r="1.1" stroke="none" />
      </svg>
      <span className="flex shrink-0 items-center gap-px">
        <span className="flex h-[11px] w-[22px] rounded-[3.5px] border border-current p-px opacity-90">
          <span className="w-[72%] rounded-[1.5px] bg-current" />
        </span>
        <span className="h-1 w-[1.5px] rounded-r-[1px] bg-current" />
      </span>
      <span className="flex h-[18px] items-center rounded-[5px] bg-[color-mix(in_srgb,var(--fg)_14%,transparent)] px-1.5 sm:h-[22px] sm:px-2">
        {/* The playhead makes the icon pale, so the look itself keeps its full strength. */}
        <span className="flex" data-hero="icon">
          <MenuIcon className="h-4 w-[17px] sm:h-5 sm:w-[21px]" look={{ ...iconLook(stance), opacity: 1 }} />
        </span>
      </span>
      <span className="tabular-nums">
        <Flow still={still}>{clock(CLOCK_START + minute)}</Flow>
      </span>
    </div>
  );
});

/**
 * A cut of the app's menu that fits the display, `minute` minutes after the lid closed: the robot beside the headline, and the agents,
 * without the bar of controls at the bottom. An agent has its folder beside its name and its line below. With `still` a number that changes does not roll.
 */
const Panel = memo(function Panel({ minute, paused, still }: { minute: number; paused: boolean; still: boolean }) {
  const line = headlineAt(minute);
  const stance = pose(line);
  const { title, subtitle } = headlineText(line);
  return (
    <PanelSurface className={`w-full shadow-[0_12px_32px_var(--shadow)] ${paused ? "panel-paused" : ""}`} label="The Agent Caffeine menu">
      {/* On a phone the head has a set height: its second line is taller with a number in it than without. */}
      <div className="flex h-12 items-center gap-2 px-2.5 sm:h-auto sm:gap-3 sm:px-4 sm:py-3">
        {/* A robot that sleeps stands still here: the one that breathes in its sleep is in the menu further down the page. On a phone it is three quarters of its size. */}
        <span className="block size-9 shrink-0 sm:size-12" data-hero="robot">
          <span className="flex w-12 origin-top-left scale-75 sm:scale-100">
            <Robot paused={paused} pose={stance} rest={stance === "asleep" ? "var(--rest)" : undefined} size={48} still={stance === "asleep"} />
          </span>
        </span>
        <p className="flex min-w-0 flex-col gap-0.5">
          <span className="text-[15px] leading-5">{title}</span>
          <span className={`text-[12px] ${MUTED}`}>
            <Flow still={still}>{subtitle}</Flow>
          </span>
        </p>
      </div>
      <div className="h-px bg-[var(--panel-line)]" />
      <ul className="flex flex-col px-[7px] py-0.5 sm:px-[13px] sm:py-1">
        {AGENTS.map((agent, place) => {
          const working = minute < agent.done;
          return (
            <li key={agent.icon} className="flex h-8 items-center gap-2 sm:h-10">
              <Mark icon={agent.icon} working={working} />
              {/* A finished agent keeps the two lines of one at work, each of a set height, so its name stays where it was. In the app an idle agent has one line. */}
              <span className="flex min-w-0 flex-1 flex-col gap-px leading-4">
                <span className={`h-4 truncate ${working ? "" : MUTED}`}>
                  {agent.name} · {agent.folder}
                </span>
                {/* The number rolls in a taller box than the line, so the line shows what runs over it, and its words stand on the line of a line without a number. */}
                <span className={`flex h-4 items-center whitespace-nowrap text-[12px] ${MUTED}`}>
                  {working ? (
                    <span>
                      <Flow still={still}>{detailOf({ state: "working", command: false, since: -agent.before * 60, before: "idle" }, minute * 60)}</Flow>
                    </span>
                  ) : (
                    // Staged, not the app's words: the app says "Finished a moment ago" for a minute and then "Idle for 9 minutes". Here a finished agent keeps one short word, so that what is done reads apart from what works.
                    "Finished"
                  )}
                </span>
              </span>
              {!working && <Check place={place} />}
            </li>
          );
        })}
      </ul>
    </PanelSurface>
  );
});

/** What of the loop changes in steps, and so is drawn again by React: the whole minutes since the lid closed, how far the lid has closed, and whether the story has just cut to another moment. */
type Beat = { minute: number; closed: number; cutting: boolean };

export function HeroScene() {
  const ref = useRef<HTMLDivElement>(null);
  const layers = useRef<HTMLDivElement>(null);
  const seen = useSeen(ref, 0.3);
  const hidden = useTabHidden();
  const play = seen && !hidden;
  const playhead = useLoop(play, heroScene.loop, heroScene.rest, MOVING);
  const reduced = useLessMotion();

  // Before the first play the scene stands at its start, which is also what the server draws.
  const [begun, setBegun] = useState(false);
  useEffect(() => {
    if (play) {
      setBegun(true);
    }
  }, [play]);

  const [beat, setBeat] = useState<Beat>({ minute: 0, closed: 0, cutting: true });
  const last = useRef({ at: 1, winding: false });
  const frame = useRef<Frame>(AT_START);
  const marked = useRef<Target[]>([]);
  const drawn = useRef<Beat>({ minute: 0, closed: 0, cutting: true });

  // One frame of the loop. The playhead winds back to the start before each
  // replay: the story cuts to its start at once, and over that time the lid
  // opens and the menu comes back from its sleep.
  const show = useCallback(
    (at: number) => {
      if (at !== last.current.at) {
        last.current = { at, winding: at < last.current.at };
      }
      const winding = last.current.winding;
      const wound = !reduced && winding ? at : null;
      const cutting = winding || !begun;
      const time = reduced ? STILL : cutting ? 0 : at * heroScene.loop;
      const closed = cut4(wound ?? stretch(time, ...heroScene.close, easeInOut));
      frame.current = {
        closed,
        dimmed: cut4(wound ?? stretch(time, ...heroScene.dim, easeInOut)),
        rest: cut4(stretch(time, ASLEEP_AT, ASLEEP_AT + TONE_DOWN, easeInOut)),
        checks: AGENTS.map((agent) => {
          const finished = secondAt(agent.done);
          return cut4(stretch(time, finished, finished + CHECK_IN));
        }),
      };
      paint(marked.current, frame.current);
      const minute = Math.floor(minutesAt(time));
      // React hears of a frame only when a step changed, which is a few dozen times in a loop.
      const now = drawn.current;
      if (now.minute !== minute || now.closed !== closed || now.cutting !== cutting) {
        drawn.current = { minute, closed, cutting };
        setBeat(drawn.current);
      }
    },
    [begun, reduced],
  );
  useMotionValueEvent(playhead, "change", show);
  useLayoutEffect(() => show(playhead.get()), [playhead, show]);
  // What React has just drawn again, such as a check that came in, takes the frame it missed.
  useLayoutEffect(() => {
    if (layers.current !== null) {
      marked.current = targets(layers.current);
      paint(marked.current, frame.current);
    }
  }, [beat]);

  const label =
    "A laptop shows the Agent Caffeine menu on its display, with three AI coding agents at work. The lid closes, and the menu stays in a dashed outline of the display: the agents keep working and finish one by one. Two minutes after the last one the menu says that the Mac can sleep";

  return (
    <div ref={ref} role="img" aria-label={label} className="flex justify-center">
      {/* The scene has a set width at each size of the page, so the menu on its display has one known scale. */}
      <div aria-hidden="true" className="w-[485px] shrink-0 min-[375px]:w-[578px] min-[390px]:w-[603px] min-[430px]:w-[670px] sm:w-[810px] lg:w-[630px] xl:w-[810px]">
        <div className="relative aspect-[100/59] w-full [container-type:inline-size] sm:aspect-[10/7]">
          {VIEWS.map(({ view, shown }) => (
            <div key={view.id} className={`absolute inset-0 ${shown}`} style={{ perspective: `${view.PERSPECTIVE}cqw`, perspectiveOrigin: `50% ${fixed(view.ORIGIN)}cqw` }}>
              {/* The lid's own glass is dark: the one desktop of the scene lies flat over it, below. */}
              <Laptop closed={beat.closed} view={view} />
            </div>
          ))}
          <div
            ref={layers}
            className="absolute"
            style={{ left: `${GLASS.left}%`, top: `${GLASS.top}cqw`, width: `${GLASS.width}%`, height: `${GLASS.height}cqw` }}
          >
            {/*
              One desktop that never moves: it lies on the glass of the open display and stays there, paler, as the lid
              goes down behind it. The page's ground under it keeps the moving lid from showing through, also while
              the menu is dim: so the ground itself never dims.
            */}
            <div className="absolute inset-0 bg-bg" style={{ borderRadius: `${GLASS.round}cqw` }} />
            <div className={`absolute inset-0 ${DESKTOP}`} data-hero="desktop" style={{ borderRadius: `${GLASS.round}cqw` }} />
            <svg className="absolute inset-0 size-full overflow-visible" data-hero="outline" fill="none" style={{ opacity: 0 }} viewBox={`0 0 ${GLASS.width} ${GLASS.height}`}>
              <rect
                height={GLASS.height}
                rx={GLASS.round}
                strokeDasharray="5 5"
                strokeWidth="1"
                style={{ stroke: "var(--hairline)" }}
                vectorEffect="non-scaling-stroke"
                width={GLASS.width}
              />
            </svg>
            <div
              className={`absolute left-1/2 top-0 flex origin-top -translate-x-1/2 flex-col items-center gap-1 ${SCALE}`}
              data-hero="menu"
              style={{ width: `calc(${GLASS.width / 100} * var(--full))`, height: `calc(${GLASS.height / 100} * var(--full))`, padding: GAP }}
            >
              <MenuBar minute={beat.minute} still={beat.cutting} />
              <div className="w-full sm:w-[320px]">
                <Panel minute={beat.minute} paused={!play} still={beat.cutting} />
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
