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
  consequence: `sleeps below ${BATTERY_FLOOR}%`,
  spoken: `Battery 27 percent, agent caffeine lets your Mac sleep below ${BATTERY_FLOOR} percent`,
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
        <Thing text="agent caffeine works the same without it. To change a setting, open it from Applications or Spotlight" title="Hide the menu bar icon">
          <Rows label="The menu bar setting in Preferences, switched off">
            <div className="flex h-9 items-center justify-between gap-3">
              <span className="truncate">Show agent caffeine in the menu bar</span>
              <SwitchCut on={false} />
            </div>
          </Rows>
        </Thing>
      </ul>
    </section>
  );
}
