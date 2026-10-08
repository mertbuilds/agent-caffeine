"use client";

import { easeInOut } from "motion/react";
import { useRef, useState } from "react";
import { AgentIcon, type AgentIconName } from "@/components/agent-icons";
import { Flow, PanelSurface } from "@/components/agents-panel";
import { lidBrightness, lidDegrees } from "@/components/laptop/geometry";
import { Laptop } from "@/components/laptop/laptop";
import { MenuIcon } from "@/components/menu-icon";
import { Robot } from "@/components/robot";
import { heroScene } from "@/lib/motion";
import { stretch, useLoop } from "@/lib/playhead";
import { useSeen } from "@/lib/use-seen";
import { useTabHidden } from "@/lib/use-tab-hidden";

/** "a" is the app over the closed laptop, "b" also carries the laptop away, and "b" and "c" end on the notification. */
export type HeroSceneCut = "a" | "b" | "c";

type Span = readonly [from: number, to: number];

const MUTED = "text-[var(--panel-muted)]";
const GREEN = "light-dark(#28a745, #32d74b)";

/** The time on the menu bar when the lid closes, in minutes of the day, and how many minutes then pass. */
const CLOCK_START = 14 * 60 + 2;
const MINUTES = 39;

/** The agents at work, the longest first as the app lists them. `before` is the minutes each has worked when the lid closes. The last one finishes. */
const AGENTS: readonly { icon: AgentIconName; name: string; folder: string; before: number }[] = [
  { icon: "claudecode", name: "Claude Code", folder: "wiki", before: 11 },
  { icon: "codex", name: "Codex", folder: "api", before: 8 },
  { icon: "cursor", name: "Cursor", folder: "website", before: 5 },
  { icon: "opencode", name: "opencode", folder: "docs", before: 3 },
];
const FINISHER = AGENTS[AGENTS.length - 1];

function clock(minutes: number): string {
  return `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, "0")}`;
}

/** An agent's mark in the slot of its ring, as in the app's menu: the arc goes round while it works, and a check stands there once it has finished. */
function Mark({ icon, finished }: { icon: AgentIconName; finished: boolean }) {
  return (
    <span className="relative flex size-[34px] shrink-0 items-center justify-center">
      <span className="flex size-7 items-center justify-center rounded-lg bg-[color-mix(in_srgb,var(--panel-fg)_8%,transparent)]">
        <AgentIcon className="size-[18px]" name={icon} />
      </span>
      <svg aria-hidden="true" className="absolute inset-0 size-full" fill="none" viewBox="0 0 34 34">
        {finished ? (
          <rect height="32.5" rx="10.25" strokeWidth="1.5" style={{ stroke: GREEN }} width="32.5" x="0.75" y="0.75" />
        ) : (
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
        )}
      </svg>
    </span>
  );
}

function Check() {
  return (
    <span aria-hidden="true" className="flex size-5 shrink-0 items-center justify-center rounded-full" style={{ background: GREEN }}>
      <svg className="size-2.5 text-white" fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.8" viewBox="0 0 10 8">
        <path d="M1 4.2 3.8 7 9 1" />
      </svg>
    </span>
  );
}

/** The right end of a Mac's menu bar: Wi-Fi, the battery, our icon with its menu open, and the clock. */
function MenuBar({ time }: { time: string }) {
  return (
    <div className="flex h-7 w-full items-center gap-3 rounded-lg bg-[color-mix(in_srgb,var(--surface)_85%,transparent)] pl-3 pr-2.5 text-[13px] text-fg backdrop-blur">
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
        <MenuIcon className="h-5 w-[21px]" held />
      </span>
      <span className="tabular-nums">
        <Flow>{time}</Flow>
      </span>
    </div>
  );
}

/** The top of the app's menu and its agents, without the bar of controls at the bottom. */
function Panel({ minutes, finished, paused }: { minutes: number; finished: boolean; paused: boolean }) {
  const working = AGENTS.length - (finished ? 1 : 0);
  return (
    <PanelSurface className={`w-full shadow-[0_12px_32px_var(--shadow)] ${paused ? "panel-paused" : ""}`} label="The agent caffeine menu">
      <div className="flex flex-col items-center px-4 pb-4 pt-3 text-center">
        <Robot paused={paused} pose="awake" />
        <p className="mt-2 text-[17px] leading-[22px]">Your Mac stays awake</p>
        <p className={`mt-0.5 ${MUTED}`}>
          <Flow>{`${working} agents are working`}</Flow>
        </p>
      </div>
      <div className="h-px bg-[var(--panel-line)]" />
      <ul className="flex flex-col px-[13px] py-2">
        {AGENTS.map((agent) => {
          const done = finished && agent === FINISHER;
          return (
            <li key={agent.name} className="flex h-11 items-center gap-2">
              <Mark finished={done} icon={agent.icon} />
              <span className="flex min-w-0 flex-1 flex-col gap-px leading-4">
                <span className="truncate">{done ? agent.name : `${agent.name} · ${agent.folder}`}</span>
                <span className={`truncate text-[12px] ${MUTED}`}>
                  {done ? "Finished a moment ago" : <Flow>{`Working for ${agent.before + minutes} minutes`}</Flow>}
                </span>
              </span>
              {done && <Check />}
            </li>
          );
        })}
      </ul>
    </PanelSurface>
  );
}

/** The notification the app sends when an agent finishes (`AgentNoticeText`): the agent, its folder, and how long it worked. */
function Notice({ shown }: { shown: number }) {
  if (shown <= 0) {
    return null;
  }
  return (
    <div
      className="absolute inset-x-0 bottom-[8%] z-20 mx-auto w-[min(19rem,92%)]"
      style={{ opacity: shown, transform: `translateY(${(shown - 1) * 12}px)` }}
    >
      <PanelSurface className="flex items-start gap-2.5 rounded-2xl p-2.5 shadow-[0_8px_24px_var(--shadow)]" label={`A notification from agent caffeine: ${FINISHER.name} finished`}>
        <img alt="" className="size-8 shrink-0" decoding="async" height={32} src="/icon.png" width={32} />
        <span className="flex min-w-0 flex-col gap-px text-[12px] leading-4">
          <span className="font-medium">{FINISHER.name} finished</span>
          <span className="font-medium">{FINISHER.folder}</span>
          <span>After {FINISHER.before + MINUTES} minutes</span>
        </span>
      </PanelSurface>
    </div>
  );
}

/** The ground going by under a laptop that is carried: short marks that slide to the left. */
function Ground({ shown, travelled }: { shown: number; travelled: number }) {
  if (shown <= 0) {
    return null;
  }
  return (
    <svg aria-hidden="true" className="absolute inset-x-[12%] bottom-[9%] h-px w-[76%] overflow-visible" style={{ opacity: shown }} viewBox="0 0 100 1" preserveAspectRatio="none">
      <line
        stroke="var(--hairline)"
        strokeDasharray="7 5"
        strokeDashoffset={travelled}
        strokeLinecap="round"
        vectorEffect="non-scaling-stroke"
        x1="0"
        x2="100"
        y1="0.5"
        y2="0.5"
      />
    </svg>
  );
}

export function HeroScene({ cut = "a" }: { cut?: HeroSceneCut }) {
  const ref = useRef<HTMLDivElement>(null);
  const seen = useSeen(ref, 0.3);
  const hidden = useTabHidden();
  const play = seen && !hidden;
  const at = useLoop(play, heroScene.loop, heroScene.rest);

  // The playhead winds back to the start before each replay. The lid opens
  // over that time, and the rest of the story stays at its end until then.
  const [last, setLast] = useState(at);
  const [winding, setWinding] = useState(false);
  if (at !== last) {
    setLast(at);
    setWinding(at < last);
  }

  const time = winding ? heroScene.loop : at * heroScene.loop;
  const span = ([from, to]: Span, ease?: (share: number) => number) => stretch(time, from, to, ease);

  const closed = winding ? at : span(heroScene.close, easeInOut);
  const minutes = Math.round(MINUTES * span(heroScene.clock, easeInOut));
  const finished = time >= heroScene.finish;
  const carried = cut === "b" ? span(heroScene.lift, easeInOut) - span(heroScene.down, easeInOut) : 0;
  const walked = cut === "b" ? span(heroScene.walk, easeInOut) : 0;
  const bob = carried * Math.sin(walked * Math.PI * 16);
  const label =
    cut === "b"
      ? "A closed laptop is carried away. The agent caffeine menu shows four AI coding agents that keep working, and a notification says when one of them has finished"
      : "A closed laptop. Above it the agent caffeine menu, open from the menu bar, shows four AI coding agents that keep working while the lid is closed. One of them finishes";

  return (
    <div ref={ref} role="img" aria-label={label} className="relative mx-auto flex w-full max-w-[22rem] flex-col items-center md:max-w-none">
      <div aria-hidden="true" className="relative z-10 flex w-full max-w-[22rem] flex-col items-center gap-1.5">
        <MenuBar time={clock(CLOCK_START + minutes)} />
        <div className="w-full max-w-[320px]">
          <Panel finished={finished} minutes={minutes} paused={!play} />
        </div>
      </div>
      {/* The closed lid's far edge is 47% of the scene's width below the scene's top, so the scene is pulled up under the menu. */}
      <div aria-hidden="true" className="-mt-[40%] w-full md:-mx-[23.23%] md:-mt-[62%] md:w-[146.46%]">
        <div className="relative aspect-[10/7] w-full [container-type:inline-size]">
          <div
            className="absolute inset-0"
            style={{ perspective: "200cqw", perspectiveOrigin: "50% 22%", transform: `translateY(${-(carried * 5 + bob * 0.6)}cqw)` }}
          >
            <Laptop closed={closed} display={lidBrightness(lidDegrees(closed))} grounded={1 - carried}>
              <div className="h-full bg-[radial-gradient(120%_90%_at_50%_100%,#2a73e8,#0b1f4d_70%)]" />
            </Laptop>
          </div>
          <Ground shown={carried} travelled={walked * 120} />
          {cut !== "a" && <Notice shown={span(heroScene.notice)} />}
        </div>
      </div>
    </div>
  );
}
