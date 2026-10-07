"use client";

import NumberFlow from "@number-flow/react";
import { useRef, type ReactNode } from "react";
import { GroupRows, PanelSurface } from "@/components/agents-panel";
import { Robot } from "@/components/robot";
import { SectionHeading } from "@/components/section-heading";
import { BATTERY_FLOOR, type Group } from "@/lib/simulator";
import { useLessMotion } from "@/lib/use-less-motion";
import { useSeen } from "@/lib/use-seen";

/** Still cuts of the app's menu, with the words of `PanelText.swift`. */
const WAITING: Group = {
  agent: "claude",
  icon: "claudecode",
  title: "Claude Code · wiki",
  state: "waiting",
  detail: "Waiting for your answer for 4 minutes",
  place: "below",
  open: null,
  children: [],
  layout: "oneLine",
};

const ONE_OF_TEN: readonly Group[] = [
  {
    agent: "claude",
    icon: "claudecode",
    title: "Claude Code",
    state: "working",
    detail: "1 working",
    place: "trailing",
    open: true,
    children: [
      { key: "wiki-6e", label: "wiki-6e", detail: "Working for 6 minutes" },
      { key: "idle", label: "9 idle sessions", detail: null },
    ],
    layout: "oneLine",
  },
  {
    agent: "codex",
    icon: "codex",
    title: "Codex",
    state: "idle",
    detail: "Idle for 6 minutes",
    place: "trailing",
    open: null,
    children: [],
    layout: "oneLine",
  },
];

/** The battery before it runs down, in percent, and how long the gauge takes, in milliseconds. */
const BATTERY_START = 34;
const DRAIN = 2400;
const DRAIN_TIMING = { duration: DRAIN, easing: "linear" };

/** A battery that runs down to the level where the app lets the Mac sleep, and the notification the app then sends. */
function BatteryStop() {
  const ref = useRef<HTMLDivElement>(null);
  const seen = useSeen(ref, 0.6);
  const lessMotion = useLessMotion();
  const low = seen || lessMotion;
  const level = low ? BATTERY_FLOOR : BATTERY_START;
  const still = lessMotion ? "0ms" : undefined;
  return (
    <div ref={ref} className="flex h-full flex-col items-center justify-center gap-4 px-4">
      <div className="flex items-center gap-3">
        <span aria-hidden="true" className="relative flex h-7 w-[58px] items-center">
          <span className="relative h-full w-[52px] rounded-lg border-[1.5px] border-[var(--panel-muted)] p-0.5">
            {/* Inner radius = outer 8px - border 1.5px - padding 2px. The charge slides, so its corners keep their shape. */}
            <span className="block h-full overflow-hidden rounded-[4.5px]">
              <span
                className="block h-full transition-[transform,background-color] ease-linear"
                style={{
                  background: low ? "light-dark(#ff3b30, #ff453a)" : "var(--fg)",
                  transform: `translateX(${level - 100}%)`,
                  transitionDuration: still ?? `${DRAIN}ms, 300ms`,
                  transitionDelay: still ?? `0ms, ${DRAIN - 300}ms`,
                }}
              />
            </span>
            {/* The level where the app stops. */}
            <span className="absolute inset-y-0.5 w-px bg-[var(--panel-muted)]" style={{ left: `calc(2px + ${BATTERY_FLOOR}% - ${(BATTERY_FLOOR / 100) * 4}px)` }} />
          </span>
          <span className="ml-0.5 h-2.5 w-[3px] rounded-r-sm bg-[var(--panel-muted)]" />
        </span>
        <span className="text-lg tabular-nums">
          <NumberFlow
            animated={!lessMotion}
            opacityTiming={DRAIN_TIMING}
            spinTiming={DRAIN_TIMING}
            transformTiming={DRAIN_TIMING}
            trend={-1}
            suffix="%"
            value={level}
          />
        </span>
      </div>
      <div
        className={`w-full max-w-[19rem] transition-[opacity,transform] duration-slow ease-smooth-out motion-reduce:transition-none ${low ? "translate-y-0 opacity-100" : "translate-y-2 opacity-0"}`}
        style={{ transitionDelay: low && !lessMotion ? `${DRAIN}ms` : "0ms" }}
      >
      <PanelSurface className="flex items-start gap-2.5 rounded-2xl p-2.5 shadow-[0_8px_24px_var(--shadow)]" label="A notification from agent caffeine">
        <img alt="" className="size-8 shrink-0" decoding="async" height={32} loading="lazy" src="/icon.png" width={32} />
        <span className="flex min-w-0 flex-col gap-px text-[12px] leading-4">
          <span className="font-medium">agent caffeine</span>
          <span className="text-pretty">agent caffeine let your Mac sleep because the battery is at {BATTERY_FLOOR}%</span>
        </span>
      </PanelSurface>
      </div>
    </div>
  );
}

function Scene({ children, text, title }: { children: ReactNode; text: string; title: string }) {
  return (
    <li className="flex flex-col rounded-[20px] border border-border p-2">
      <div className="h-44 overflow-hidden rounded-xl bg-surface">{children}</div>
      <div className="flex flex-col gap-1.5 px-2 pb-2 pt-4">
        <h3 className="text-balance font-medium leading-snug">{title}</h3>
        <p className="text-pretty text-sm leading-relaxed text-muted">{text}</p>
      </div>
    </li>
  );
}

export function SleepScenes() {
  return (
    <section id="features" className="mx-auto flex w-full max-w-[1120px] scroll-mt-20 flex-col gap-10">
      <SectionHeading lead="It keeps your Mac awake for work, and for nothing else" title="It lets your Mac sleep at the right time" />
      <ul className="mx-auto grid w-full max-w-[36rem] gap-4 lg:max-w-none lg:grid-cols-3">
        <Scene
          text="agent caffeine keeps your Mac awake for 5 minutes, so you can answer. After that your Mac can sleep. You can change the time"
          title="An agent asks you something while you are away"
        >
          <PanelSurface className="panel-still flex h-full flex-col justify-center rounded-none border-0" label="The agent caffeine menu while Claude Code waits for you">
            <div className="flex items-center gap-3 px-4 pb-3">
              <Robot pose="attentive" size={56} still />
              <p className="flex min-w-0 flex-col gap-0.5">
                <span className="text-[15px] leading-5">Your Mac stays awake</span>
                <span className="text-pretty text-[12px] text-[var(--panel-muted)]">Claude Code is waiting for you, can sleep in 1 minute</span>
              </p>
            </div>
            <div className="h-px bg-[var(--panel-line)]" />
            <div className="px-[13px] pt-2">
              <GroupRows group={WAITING} />
            </div>
          </PanelSurface>
        </Scene>
        <Scene
          text={`Your agents keep working. On battery, macOS asks you once to allow a small helper. agent caffeine lets your Mac sleep at ${BATTERY_FLOOR}% battery and when it gets too hot. Do not put a working Mac in a closed bag`}
          title="The lid is closed and your Mac runs on battery"
        >
          <BatteryStop />
        </Scene>
        <Scene
          text="A session is one open chat with an agent. Only the one that works keeps your Mac awake"
          title="10 sessions are open and 1 is working"
        >
          <PanelSurface className="panel-still flex h-full flex-col justify-center rounded-none border-0 px-[13px]" label="The agent caffeine menu with one working session and nine idle ones">
            {ONE_OF_TEN.map((group) => (
              <GroupRows key={group.agent} group={group} />
            ))}
          </PanelSurface>
        </Scene>
      </ul>
    </section>
  );
}
