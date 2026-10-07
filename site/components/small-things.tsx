import type { ReactNode } from "react";
import { BatteryLine, Gear, PanelSurface, TimerChoices } from "@/components/agents-panel";
import { Robot } from "@/components/robot";
import { SectionHeading } from "@/components/section-heading";
import { BATTERY_FLOOR, type Battery } from "@/lib/simulator";

/** Still cuts of the app, with the words of `PanelText.swift`, `AgentNotices.swift` and `PreferencesView.swift`. */
const MUTED = "text-[var(--panel-muted)]";
const LINE = "h-px bg-[var(--panel-line)]";

const NEAR_FLOOR: Battery = {
  percent: 27,
  floor: BATTERY_FLOOR,
  level: "nearFloor",
  charge: "27%",
  consequence: `sleeps at ${BATTERY_FLOOR}%`,
  spoken: `Battery 27 percent, agent caffeine lets your Mac sleep at ${BATTERY_FLOOR} percent`,
};

/** The two shortcuts of Preferences > Shortcuts (`ShortcutAction.title`), each with keys a reader could record. */
const SHORTCUTS = [
  { title: "Turn agent caffeine on or off", keys: "⌥⌘L" },
  { title: "Pause for 1 hour", keys: "⌥⌘P" },
];

/** The switch of the app, drawn in one state. */
function SwitchCut({ on }: { on: boolean }) {
  return (
    <span
      aria-hidden="true"
      className={`flex h-5 w-11 shrink-0 items-center rounded-full p-0.5 ${on ? "bg-[var(--app-blue)]" : "bg-[color-mix(in_srgb,var(--panel-fg)_20%,transparent)]"}`}
    >
      <span className={`h-4 w-[26px] rounded-full bg-white shadow-[0_1px_2px_rgba(0,0,0,0.25)] ${on ? "translate-x-[14px]" : ""}`} />
    </span>
  );
}

/** A group of rows in Preferences. */
function Rows({ children, label }: { children: ReactNode; label: string }) {
  return (
    <PanelSurface className="w-full max-w-[19rem] rounded-[10px] bg-[color-mix(in_srgb,var(--panel-fg)_4%,var(--panel))] px-3" label={label}>
      {children}
    </PanelSurface>
  );
}

/** The lid from the side at three angles, with the share of your brightness `LidDimming.curve` gives at each. */
const LIDS = [
  { angle: 105, level: 1, label: "105°" },
  { angle: 24, level: 0.5, label: "24°" },
  { angle: 0, level: 0, label: "0°" },
];
const LID_STEP = 94;
const DISPLAY_OFF = "color-mix(in srgb, var(--hairline) 15%, black)";

/** A still side view: the hero is the one place where the lid moves. */
function LidCut() {
  return (
    <svg
      aria-label="A laptop from the side at three lid angles. At 105 degrees the display is bright, at 24 degrees it is at half brightness, and with the lid closed it is off"
      className="w-full max-w-[22rem]"
      role="img"
      viewBox="0 0 300 98"
    >
      <defs>
        <linearGradient id="lid-cut-light" x1="0" x2="0" y1="0" y2="1">
          <stop offset="0" style={{ stopColor: "var(--accent)", stopOpacity: 0.5 }} />
          <stop offset="1" style={{ stopColor: "var(--accent)", stopOpacity: 0 }} />
        </linearGradient>
        <filter height="300%" id="lid-cut-soft" width="200%" x="-50%" y="-100%">
          <feGaussianBlur stdDeviation="3" />
        </filter>
        <clipPath id="lid-cut-above">
          <rect height="70" width="300" x="-40" />
        </clipPath>
        <clipPath id="lid-cut-front">
          <rect height="60" width="110" x="-24" y="70" />
        </clipPath>
      </defs>
      {LIDS.map((lid, index) => (
        <g key={lid.label} transform={`translate(${32 + index * LID_STEP} 0)`}>
          <g clipPath="url(#lid-cut-above)">
            <g clipPath="url(#lid-cut-front)" transform={`rotate(${-lid.angle} 0 70)`}>
              <rect fill="url(#lid-cut-light)" filter="url(#lid-cut-soft)" height="36" opacity={lid.level} width="54" x="4" y="70" />
            </g>
          </g>
          <rect height="5" rx="2" style={{ fill: "var(--bg)", stroke: "var(--hairline)" }} width="62" x="0" y="70" />
          <g transform={`rotate(${-lid.angle} 0 70)`}>
            <rect height="4" rx="1.5" style={{ fill: "var(--bg)", stroke: "var(--hairline)" }} width="62" x="0" y="66" />
            <rect height="2" style={{ fill: DISPLAY_OFF }} width="54" x="4" y="68" />
            <rect height="2" opacity={lid.level} style={{ fill: "var(--accent)" }} width="54" x="4" y="68" />
          </g>
          <text className="tabular-nums" fontSize="11" style={{ fill: "var(--muted)" }} textAnchor="middle" x="31" y="94">
            {lid.label}
          </text>
        </g>
      ))}
    </svg>
  );
}

function Thing({ children, text, title }: { children: ReactNode; text: string; title: string }) {
  return (
    <li className="flex flex-col rounded-[20px] border border-border p-2">
      <div className="flex h-32 items-center justify-center overflow-hidden rounded-xl bg-surface px-4">{children}</div>
      <div className="flex flex-col gap-1.5 px-2 pb-2 pt-4">
        <h3 className="text-balance font-medium leading-snug">{title}</h3>
        <p className="text-pretty text-sm leading-relaxed text-muted">{text}</p>
      </div>
    </li>
  );
}

export function SmallThings() {
  return (
    <section id="small-things" className="mx-auto flex w-full max-w-[1120px] scroll-mt-20 flex-col gap-10">
      <SectionHeading lead="Each one is in the menu or in Preferences" title="It does the small things too" />
      <ul className="mx-auto grid w-full max-w-[36rem] gap-4 sm:grid-cols-2 lg:max-w-none lg:grid-cols-3">
        <Thing
          text="It dims from 45 degrees and is off with the lid closed, so it does not use battery or warm your Mac"
          title="The display dims as the lid closes"
        >
          <LidCut />
        </Thing>
        <Thing
          text="Your Mac stays awake for 1, 2 or 4 hours, so a message from your phone reaches your agent"
          title="Stay reachable from your phone"
        >
          <PanelSurface className="panel-still w-full max-w-[19rem]" label="The agent caffeine menu while your Mac stays reachable until 11:41">
            <div className="flex items-center gap-3 px-4 py-2.5">
              <Robot pose="reachable" size={40} still />
              <p className="flex min-w-0 flex-col gap-0.5">
                <span className="text-[15px] leading-5">Your Mac stays awake</span>
                <span className={`text-[12px] tabular-nums ${MUTED}`}>Reachable until 11:41</span>
              </p>
            </div>
            <div className={LINE} />
            <div aria-hidden="true" className="flex items-center gap-2 px-4 py-1.5">
              <span className={`tabular-nums ${MUTED}`}>Reachable until 11:41</span>
              <span className="text-accent">Stop</span>
              <span className="flex-1" />
              <Gear />
              <SwitchCut on />
            </div>
          </PanelSurface>
        </Thing>
        <Thing text="Pause for 30 minutes, 1 hour or until tomorrow. agent caffeine starts again by itself" title="Pause it for a while">
          <PanelSurface className="rounded-[10px] p-[5px] shadow-[0_8px_24px_var(--shadow)]" label="The timer menu: pause for 30 minutes, for 1 hour or until tomorrow">
            <ul aria-hidden="true">
              <TimerChoices active={1} bar={{ reachable: false, reachableCost: null }} />
            </ul>
          </PanelSurface>
        </Thing>
        <Thing
          text="A notification when an agent waits for your answer, and one when it finishes. Each has its own switch"
          title="It tells you when an agent needs you"
        >
          <PanelSurface
            className="flex w-full max-w-[19rem] items-start gap-2.5 rounded-2xl p-2.5 shadow-[0_8px_24px_var(--shadow)]"
            label="A notification from agent caffeine: Claude Code is waiting for you"
          >
            <img alt="" className="size-8 shrink-0" decoding="async" height={32} loading="lazy" src="/icon.png" width={32} />
            <span className="flex min-w-0 flex-col gap-px text-[12px] leading-4">
              <span className="font-medium">Claude Code is waiting for you</span>
              <span className="font-medium">wiki</span>
              <span>Your Mac can sleep in 5 minutes</span>
            </span>
          </PanelSurface>
        </Thing>
        <Thing text="On battery the menu shows the charge, and the level where agent caffeine lets your Mac sleep" title="You see how much battery is left">
          <PanelSurface className="flex w-full max-w-[19rem] justify-center px-4 py-3.5" label="The line of the battery in the agent caffeine menu">
            <BatteryLine battery={NEAR_FLOOR} />
          </PanelSurface>
        </Thing>
        <Thing text="Switch agent caffeine on or off, or pause it for 1 hour, with keys you choose. They work in every app" title="Keyboard shortcuts">
          <Rows label="The keyboard shortcuts in Preferences">
            {SHORTCUTS.map((shortcut, index) => (
              <div key={shortcut.title}>
                {index > 0 && <div className={LINE} />}
                <div className="flex h-9 items-center justify-between gap-3">
                  <span className="truncate">{shortcut.title}</span>
                  <span className="flex h-[22px] min-w-[68px] shrink-0 items-center justify-center rounded-md bg-[color-mix(in_srgb,var(--panel-fg)_10%,transparent)] px-2 shadow-[inset_0_0_0_0.5px_var(--panel-line)]">
                    {shortcut.keys}
                  </span>
                </div>
              </div>
            ))}
          </Rows>
        </Thing>
      </ul>
    </section>
  );
}
