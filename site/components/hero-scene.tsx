"use client";

import { easeInOut } from "motion/react";
import { useEffect, useRef, useState } from "react";
import { AgentIcon, type AgentIconName } from "@/components/agent-icons";
import { Flow, PanelSurface } from "@/components/agents-panel";
import { Laptop } from "@/components/laptop/laptop";
import { MenuIcon } from "@/components/menu-icon";
import { Robot } from "@/components/robot";
import { heroScene } from "@/lib/motion";
import { stretch, useLoop } from "@/lib/playhead";
import { RELEASE_AFTER, detailOf, headlineText, iconLook, pose, type Headline, type IconLook, type Pose } from "@/lib/simulator";
import { useLessMotion } from "@/lib/use-less-motion";
import { useSeen } from "@/lib/use-seen";
import { useTabHidden } from "@/lib/use-tab-hidden";

type Span = readonly [from: number, to: number];

const MUTED = "text-[var(--panel-muted)]";
const GREEN = "light-dark(#28a745, #32d74b)";

/** The time on the menu bar when the lid closes, in minutes of the day. */
const CLOCK_START = 14 * 60 + 2;
/**
 * The glass of the open display in the scene, in hundredths of the scene's
 * width (`lidArt(0)` less the bezel and the chin). The open lid faces the eye,
 * so the glass is a plain rectangle, and the flat menu lies on it.
 */
const GLASS = { left: 23.07, top: 6.21, width: 53.86, height: 35, round: 0.87 };
/** The scene's width at which the menu is drawn at its own size, and the glass at that width, in pixels. */
const FULL = 705;
const BOX = { width: (GLASS.width * FULL) / 100, height: (GLASS.height * FULL) / 100 };
/** The gap between the glass's edge and the menu bar, in pixels at full size. */
const GAP = 3;

/** Seconds the check takes to come in. */
const CHECK_IN = 0.35;
/** The Mac's desktop, and how much of itself it keeps in the outline of the display once the lid is closed. */
const DESKTOP = "bg-[radial-gradient(130%_100%_at_50%_100%,#3b82f0,#12306e_65%,#0a1c44)]";
const DESKTOP_KEPT = 0.45;
/** Seconds the robot's tile takes to lose its colour, and the icon in the menu bar to go pale, once the Mac can sleep. */
const TONE_DOWN = 0.8;
/** How much of itself the menu keeps once the Mac sleeps. */
const ASLEEP = 0.45;
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

type Row = { icon: AgentIconName; title: string; detail: string; working: boolean; checked: number };

function clock(minutes: number): string {
  return `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, "0")}`;
}

/** An agent's mark in the slot of its ring, as in the app's menu: the arc goes round while it works, and an idle agent's mark is pale and has no ring. */
function Mark({ icon, working }: { icon: AgentIconName; working: boolean }) {
  return (
    <span className="relative flex size-[34px] shrink-0 items-center justify-center">
      <span className={`flex size-7 items-center justify-center rounded-lg bg-[color-mix(in_srgb,var(--panel-fg)_8%,transparent)] ${working ? "" : "opacity-55"}`}>
        <AgentIcon className="size-[18px]" name={icon} />
      </span>
      {working && (
        <svg aria-hidden="true" className="absolute inset-0 size-full" fill="none" viewBox="0 0 34 34">
          <rect
            className="ring-sweep"
            height="32.5"
            pathLength="1"
            rx="10.25"
            stroke="var(--app-blue)"
            strokeDasharray="0.75 0.25"
            strokeLinecap="round"
            strokeWidth="1.5"
            width="32.5"
            x="0.75"
            y="0.75"
          />
        </svg>
      )}
    </span>
  );
}

/** The check of an agent that has finished. It comes in over `shown`, from 0 to 1. */
function Check({ shown }: { shown: number }) {
  return (
    <span
      aria-hidden="true"
      className="flex size-4 shrink-0 items-center justify-center rounded-full"
      style={{ background: GREEN, opacity: shown, transform: `scale(${0.6 + 0.4 * shown})` }}
    >
      <svg className="size-2 text-white" fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.8" viewBox="0 0 10 8">
        <path d="M1 4.2 3.8 7 9 1" />
      </svg>
    </span>
  );
}

/** The Mac's menu bar along the top of the display: the Apple mark, Wi-Fi, the battery, our icon with its menu open, and the clock. Its corners are the display's, less the gap round it. */
function MenuBar({ time, look, still }: { time: string; look: IconLook; still: boolean }) {
  return (
    <div className="flex h-6 w-full items-center gap-3 rounded-[4px] bg-[color-mix(in_srgb,var(--surface)_88%,transparent)] pl-2.5 pr-2 text-[13px] text-fg backdrop-blur">
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
      <span className="flex h-[22px] items-center rounded-[5px] bg-[color-mix(in_srgb,var(--fg)_14%,transparent)] px-2">
        <MenuIcon className="h-5 w-[21px]" look={look} />
      </span>
      <span className="tabular-nums">
        <Flow still={still}>{time}</Flow>
      </span>
    </div>
  );
}

/**
 * A cut of the app's menu that fits the display: the robot beside the headline, and the agents, without the bar of controls at the bottom.
 * An agent has its folder beside its name and its line below. `rest` is how far the robot's tile has lost its colour. With `still` a number that changes does not roll.
 */
function Panel({ title, subtitle, stance, rest, rows, paused, still }: { title: string; subtitle: string; stance: Pose; rest: number; rows: readonly Row[]; paused: boolean; still: boolean }) {
  return (
    <PanelSurface className={`w-full shadow-[0_12px_32px_var(--shadow)] ${paused ? "panel-paused" : ""}`} label="The Agent Caffeine menu">
      <div className="flex items-center gap-3 px-4 py-3">
        {/* A robot that sleeps stands still here: the one that breathes in its sleep is in the menu further down the page. */}
        <Robot paused={paused} pose={stance} rest={rest} size={48} still={stance === "asleep"} />
        <p className="flex min-w-0 flex-col gap-0.5">
          <span className="text-[15px] leading-5">{title}</span>
          <span className={`text-[12px] ${MUTED}`}>
            <Flow still={still}>{subtitle}</Flow>
          </span>
        </p>
      </div>
      <div className="h-px bg-[var(--panel-line)]" />
      <ul className="flex flex-col px-[13px] py-1">
        {rows.map((row) => (
          <li key={row.icon} className="flex h-10 items-center gap-2">
            <Mark icon={row.icon} working={row.working} />
            {/* A finished agent keeps the two lines of one at work, each of a set height, so its name stays where it was. In the app an idle agent has one line. */}
            <span className="flex min-w-0 flex-1 flex-col gap-px leading-4">
              <span className={`h-4 truncate ${row.working ? "" : MUTED}`}>{row.title}</span>
              <span className={`h-4 truncate text-[12px] ${MUTED}`}>
                <Flow still={still}>{row.detail}</Flow>
              </span>
            </span>
            {!row.working && <Check shown={row.checked} />}
          </li>
        ))}
      </ul>
    </PanelSurface>
  );
}

type Hold = { time?: number; wind?: number };

/**
 * For a look at one moment of the loop while the site is developed:
 * `window.dispatchEvent(new CustomEvent("hero-hold", { detail: { time: 1.6 } }))`
 * holds the scene at that second, `{ wind: 0.5 }` holds it half way through
 * the wind back, and `{ detail: null }` lets it go. A production build never holds.
 */
function useHold(): Hold | null {
  const [hold, setHold] = useState<Hold | null>(null);
  useEffect(() => {
    if (process.env.NODE_ENV !== "development") {
      return;
    }
    const onHold = (event: Event) => setHold(event instanceof CustomEvent ? (event.detail as Hold | null) : null);
    window.addEventListener("hero-hold", onHold);
    return () => window.removeEventListener("hero-hold", onHold);
  }, []);
  return hold;
}

export function HeroScene() {
  const ref = useRef<HTMLDivElement>(null);
  const seen = useSeen(ref, 0.3);
  const hidden = useTabHidden();
  const play = seen && !hidden;
  const at = useLoop(play, heroScene.loop, heroScene.rest);

  const reduced = useLessMotion();
  // Before the first play the scene stands at its start, which is also what the server draws.
  const [begun, setBegun] = useState(false);
  useEffect(() => {
    if (play) {
      setBegun(true);
    }
  }, [play]);

  // The playhead winds back to the start before each replay. The story cuts
  // to its start at once, and over that time the lid opens and the menu
  // comes back from its sleep.
  const [last, setLast] = useState(at);
  const [winding, setWinding] = useState(false);
  if (at !== last) {
    setLast(at);
    setWinding(at < last);
  }

  const hold = useHold();
  const wound = hold !== null ? (hold.wind ?? null) : !reduced && winding ? at : null;
  const cutting = hold !== null || winding || !begun;
  const time = hold !== null ? (hold.time ?? 0) : reduced ? STILL : cutting ? 0 : at * heroScene.loop;
  const span = ([from, to]: Span, ease?: (share: number) => number) => stretch(time, from, to, ease);

  const closed = wound ?? span(heroScene.close, easeInOut);
  const dimmed = wound ?? span(heroScene.dim, easeInOut);
  const minutes = minutesAt(time);
  const line = headlineAt(minutes);
  const stance = pose(line);
  const rows: Row[] = AGENTS.map((agent) => {
    const working = minutes < agent.done;
    const finished = secondAt(agent.done);
    return {
      icon: agent.icon,
      title: `${agent.name} · ${agent.folder}`,
      // Staged, not the app's words: the app says "Finished a moment ago" for a minute and then "Idle for 9 minutes". Here a finished agent keeps one short word, so that what is done reads apart from what works.
      detail: working ? detailOf({ state: "working", command: false, since: -agent.before * 60, before: "idle" }, minutes * 60) : "Finished",
      working,
      checked: stretch(time, finished, finished + CHECK_IN),
    };
  });
  const label =
    "A laptop shows the Agent Caffeine menu on its display, with three AI coding agents at work. The lid closes, and the menu stays in a dashed outline of the display: the agents keep working and finish one by one. Two minutes after the last one the menu says that the Mac can sleep";

  // The robot's tile loses its colour and the icon in the menu bar goes pale over the same time, once the Mac can sleep.
  const rest = stretch(time, ASLEEP_AT, ASLEEP_AT + TONE_DOWN, easeInOut);
  const icon = iconLook(stance);

  // How much of themselves the desktop, the outline and the menu show: less once the Mac sleeps.
  const lit = 1 - (1 - ASLEEP) * dimmed;

  return (
    <div ref={ref} role="img" aria-label={label} className="flex justify-center">
      {/* The scene has a set width at each size of the page, so the menu on its display has one known scale. */}
      <div aria-hidden="true" className="w-[660px] shrink-0 sm:w-[810px] lg:w-[630px] xl:w-[810px]">
        <div className="relative aspect-[10/7] w-full [container-type:inline-size]">
          <div className="absolute inset-0" style={{ perspective: "200cqw", perspectiveOrigin: "50% 22%" }}>
            {/* The lid's own glass is dark: the one desktop of the scene lies flat over it, below. */}
            <Laptop closed={closed} />
          </div>
          <div
            className="absolute"
            style={{ left: `${GLASS.left}%`, top: `${GLASS.top}cqw`, width: `${GLASS.width}%`, height: `${GLASS.height}cqw` }}
          >
            {/*
              One desktop that never moves: it lies on the glass of the open display and stays there, paler, as the lid
              goes down behind it. The page's ground under it keeps the moving lid from showing through, also while
              the menu is dim: so the ground itself never dims.
            */}
            <div className="absolute inset-0 bg-bg" style={{ borderRadius: `${GLASS.round}cqw` }} />
            <div className={`absolute inset-0 ${DESKTOP}`} style={{ borderRadius: `${GLASS.round}cqw`, opacity: (1 - (1 - DESKTOP_KEPT) * closed) * lit }} />
            <svg className="absolute inset-0 size-full overflow-visible" fill="none" style={{ opacity: closed * lit }} viewBox={`0 0 ${GLASS.width} ${GLASS.height}`}>
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
              className="absolute left-1/2 top-0 flex origin-top -translate-x-1/2 scale-[calc(660/705)] flex-col items-center gap-1 sm:scale-[calc(810/705)] lg:scale-[calc(630/705)] xl:scale-[calc(810/705)]"
              style={{ width: BOX.width, height: BOX.height, padding: GAP, opacity: lit }}
            >
              <MenuBar look={{ ...icon, opacity: 1 + (icon.opacity - 1) * rest }} still={cutting} time={clock(CLOCK_START + Math.floor(minutes))} />
              <div className="w-[320px]">
                <Panel {...headlineText(line)} paused={!play} rest={rest} rows={rows} stance={stance} still={cutting} />
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
