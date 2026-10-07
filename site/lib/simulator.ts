import type { AgentIconName } from "@/components/agent-icons";

/**
 * A model of the app's decisions, mirrored from the Swift source: the hold
 * (`Detection/HoldPolicy.swift`), the safety stop (`Power/SafetyMonitor.swift`),
 * the pause and its mirror (`Detection/Pause.swift`, `Reachable.swift`), the
 * words and rows of the menu (`UI/Panel/Model/PanelText.swift`,
 * `MenuModel.swift`) and the poses of the robot (`RobotLook.swift`,
 * `MenuBarLook.swift`). Every function is pure. Times are in simulated seconds.
 * Both agents here report their own state, as Claude Code and Codex do.
 */

export type Mode = "always" | "agentOpen" | "agentWorking";
export type Power = "adapter" | "battery";
export type Lid = "open" | "closed";
export type AgentId = "claude" | "codex";
export type WorkState = "working" | "waiting" | "idle";
/** What the reader can set an agent to. */
export type Choice = WorkState | "closed";

export type Session = {
  key: string;
  agent: AgentId;
  /** The session's name, or its folder. */
  name: string;
  /** What the agent says about itself. */
  state: WorkState;
  /** A command the agent started is still busy. */
  command: boolean;
  /** When it entered the state it counts as now. */
  since: number;
  /** The state it left, or null when it was first seen in this one. */
  before: WorkState | null;
  lastWorkingAt: number | null;
  waitingSince: number | null;
};

export type SimState = {
  enabled: boolean;
  mode: Mode;
  power: Power;
  lid: Lid;
  /** The lid closed helper is allowed. */
  helper: boolean;
  hintDismissed: boolean;
  /** Percent. */
  battery: number;
  /** `SafetyMonitor.batteryStopped`: a battery stop lasts until the level is back above the floor. */
  batteryStopped: boolean;
  /** `Pause.until`: agent caffeine acts as if it were off until then. Null when not paused. */
  pausedUntil: number | null;
  /** `Reachable.until`: the Mac stays awake until then, also when no agent works. Null when not on. */
  reachableUntil: number | null;
  sessions: readonly Session[];
  /** Idle sessions that are counted and not named. */
  idleExtra: Readonly<Record<AgentId, number>>;
  now: number;
};

/** `AwakeMode.title` and `AwakeMode.shortTitle`. */
export const MODES: readonly { mode: Mode; title: string; short: string }[] = [
  { mode: "always", title: "Always", short: "Always" },
  { mode: "agentOpen", title: "While an agent is open", short: "While open" },
  { mode: "agentWorking", title: "While an agent is working", short: "While working" },
];

export const AGENTS: readonly { id: AgentId; name: string; folder: string; icon: AgentIconName }[] = [
  { id: "claude", name: "Claude Code", folder: "wiki", icon: "claudecode" },
  { id: "codex", name: "Codex", folder: "website", icon: "codex" },
];

/** `DetectionSettings.waitingHold`. */
export const WAITING_HOLD = 300;
/** `DetectionSettings.releaseAfterState`. */
export const RELEASE_AFTER = 120;
/** `SafetyMonitor.defaultBatteryFloorPercent` and `batteryRecoveryPoints`. */
export const BATTERY_FLOOR = 20;
export const BATTERY_RECOVERY = 5;
/** `MenuModel.batteryWarningPoints`: the line of the battery turns amber this many points above the floor. */
export const BATTERY_WARNING = 10;
export const BATTERY_LEVELS = [58, 27, BATTERY_FLOOR] as const;
/** `Reachable.batteryPercentPerHour`. */
export const REACHABLE_COST = 1;
/** The time of day when the simulation starts, in seconds. The menu bar's clock runs on from it with the simulated time. */
export const CLOCK = 9 * 3600 + 41 * 60;

/** `PauseChoice` and `ReachableChoice`, with the titles of `PanelText.title(of:)`. */
export type PauseChoice = "thirtyMinutes" | "oneHour" | "untilTomorrow";
export type ReachableChoice = "oneHour" | "twoHours" | "fourHours";

export const PAUSES: readonly { choice: PauseChoice; title: string }[] = [
  { choice: "thirtyMinutes", title: "Pause for 30 minutes" },
  { choice: "oneHour", title: "Pause for 1 hour" },
  { choice: "untilTomorrow", title: "Pause until tomorrow" },
];

export const REACHABLES: readonly { choice: ReachableChoice; title: string; hours: number }[] = [
  { choice: "oneHour", title: "Stay reachable for 1 hour", hours: 1 },
  { choice: "twoHours", title: "Stay reachable for 2 hours", hours: 2 },
  { choice: "fourHours", title: "Stay reachable for 4 hours", hours: 4 },
];
/** Simulated seconds per real second, so the waiting hold runs out in six seconds. */
export const SPEED = 50;

const NO_EXTRA: Record<AgentId, number> = { claude: 0, codex: 0 };

// MARK: Presets

export type PresetId = "working" | "waiting" | "build" | "idle" | "reachable" | "lid" | "low";

/** `point` is what the situation shows, in the words of the page and not of the menu. */
export const PRESETS: readonly { id: PresetId; title: string; point: string }[] = [
  { id: "working", title: "Agent working", point: "Claude Code and Codex are in the middle of their work. Your Mac does not sleep, also when you leave it alone" },
  {
    id: "waiting",
    title: "Waiting for you",
    point: "Claude Code asked you a question. Your Mac stays awake for 5 minutes, so you can answer. After that it can sleep",
  },
  {
    id: "build",
    title: "Build still running",
    point: "Claude Code is done, but a build it started still runs. Your Mac stays awake until the build ends",
  },
  { id: "idle", title: "All idle", point: "Many sessions are open, but no agent has work. Nothing keeps your Mac awake" },
  {
    id: "reachable",
    title: "Stay reachable",
    point: "No agent has work, but you want to send one a message from your phone. Your Mac stays awake for 2 hours",
  },
  {
    id: "lid",
    title: "On battery, lid closed",
    point: "The lid is closed and your Mac is on battery. With the helper allowed, your agents keep working",
  },
  {
    id: "low",
    title: "Battery low",
    point: "The battery went down to 20% while an agent worked. agent caffeine stops there, so your Mac can sleep before the battery is empty",
  },
];

function session(agent: AgentId, name: string, state: WorkState, since: number, more: Partial<Session> = {}): Session {
  return {
    key: `${agent}-${name}`,
    agent,
    name,
    state,
    command: false,
    since,
    before: null,
    lastWorkingAt: null,
    waitingSince: state === "waiting" ? since : null,
    ...more,
  };
}

/** Sets the whole state to a situation, keeping the clock. */
export function preset(state: SimState, id: PresetId): SimState {
  const now = state.now;
  const ago = (minutes: number) => now - minutes * 60;
  const base: SimState = {
    enabled: true,
    mode: "agentWorking",
    power: "adapter",
    lid: "open",
    helper: false,
    hintDismissed: false,
    battery: BATTERY_LEVELS[0],
    batteryStopped: false,
    pausedUntil: null,
    reachableUntil: null,
    sessions: [],
    idleExtra: NO_EXTRA,
    now,
  };
  switch (id) {
    case "working":
      return {
        ...base,
        sessions: [
          session("claude", "wiki-6e", "working", ago(6.5), { before: "idle" }),
          session("codex", "website", "working", ago(3.2), { before: "idle" }),
        ],
        idleExtra: { claude: 8, codex: 0 },
      };
    case "waiting":
      return {
        ...base,
        sessions: [
          session("claude", "wiki", "waiting", now, { before: "working", lastWorkingAt: ago(10) }),
          session("codex", "website", "idle", ago(25.5)),
        ],
      };
    case "build":
      return {
        ...base,
        sessions: [
          session("claude", "site", "idle", ago(3.2), { command: true, before: "idle" }),
          session("codex", "website", "idle", ago(40.5)),
        ],
      };
    case "idle":
      return {
        ...base,
        sessions: [session("claude", "wiki", "idle", ago(7.5)), session("codex", "website", "idle", ago(6.4))],
        idleExtra: { claude: 9, codex: 1 },
      };
    case "reachable":
      return {
        ...base,
        power: "battery",
        helper: true,
        reachableUntil: now + 2 * 3600,
        sessions: [session("claude", "wiki", "idle", ago(12.5)), session("codex", "website", "idle", ago(82.5))],
      };
    case "lid":
      return {
        ...base,
        power: "battery",
        lid: "closed",
        helper: true,
        sessions: [session("claude", "wiki", "working", ago(12.5), { before: "idle" })],
      };
    case "low":
      return withSafety({
        ...base,
        power: "battery",
        lid: "closed",
        helper: true,
        battery: BATTERY_FLOOR,
        sessions: [
          session("claude", "wiki", "working", ago(82.5), { before: "idle" }),
          session("codex", "website", "idle", ago(40.5)),
        ],
      });
  }
}

export const INITIAL: SimState = preset(
  {
    enabled: true,
    mode: "agentWorking",
    power: "adapter",
    lid: "open",
    helper: false,
    hintDismissed: false,
    battery: BATTERY_LEVELS[0],
    batteryStopped: false,
    pausedUntil: null,
    reachableUntil: null,
    sessions: [],
    idleExtra: NO_EXTRA,
    now: 0,
  },
  "working",
);

// MARK: Demo

/**
 * The examples that play until the reader first touches the simulator: each
 * situation is chosen, then held for `hold` real milliseconds. The loop starts
 * with the situation of `INITIAL`.
 */
export const DEMO: readonly { preset: PresetId; hold: number }[] = [
  { preset: "working", hold: 3000 },
  // Long enough for the waiting hold to run out and the outcome to be read.
  { preset: "waiting", hold: 8500 },
  { preset: "build", hold: 3200 },
  { preset: "idle", hold: 2800 },
  { preset: "reachable", hold: 3400 },
  { preset: "lid", hold: 3200 },
  { preset: "low", hold: 3800 },
];

/** Before the first step, in real milliseconds. */
const DEMO_LEAD = 700;
/** The pointer going to a control, and pressing it, in real milliseconds. */
export const DEMO_MOVE = 600;
export const DEMO_PRESS = 150;

/** Where the demo is: holding the situation of `DEMO[step]` (or waiting to begin), or moving to and pressing the one after it. */
export type Cue = { step: number; phase: "lead" | "hold" | "move" | "press" };

export const DEMO_START: Cue = { step: 0, phase: "lead" };

/** The situation chosen while the pointer moves and presses. */
export function upcoming(cue: Cue): PresetId {
  return DEMO[(cue.step + 1) % DEMO.length].preset;
}

/** How long a cue lasts, in real milliseconds. */
export function cueTime(cue: Cue): number {
  switch (cue.phase) {
    case "lead":
      return DEMO_LEAD;
    case "hold":
      return DEMO[cue.step].hold;
    case "move":
      return DEMO_MOVE;
    case "press":
      return DEMO_PRESS;
  }
}

/** The cue after this one; a new `step` means its situation is to be applied. */
export function nextCue(cue: Cue): Cue {
  switch (cue.phase) {
    case "lead":
    case "hold":
      return { ...cue, phase: "move" };
    case "move":
      return { ...cue, phase: "press" };
    case "press":
      return { step: (cue.step + 1) % DEMO.length, phase: "hold" };
  }
}

/** The `data-demo` name of the control the pointer is at or going to, or null before the first step. */
export function cueTarget(cue: Cue): string | null {
  switch (cue.phase) {
    case "lead":
      return null;
    case "hold":
      return `preset-${DEMO[cue.step].preset}`;
    case "move":
    case "press":
      return `preset-${upcoming(cue)}`;
  }
}

// MARK: Controls

/** A busy command counts as work, whatever the agent says: a turn that ended is not work that ended (`VerdictRules`). */
export function verdict(run: Session): WorkState {
  return run.command ? "working" : run.state;
}

/** What the reader's control for an agent shows. */
export function choiceOf(state: SimState, agent: AgentId): Choice {
  const first = state.sessions.find((run) => run.agent === agent);
  if (first !== undefined) return verdict(first);
  return state.idleExtra[agent] > 0 ? "idle" : "closed";
}

/** Puts an agent into a state: its named sessions become one session in that state. Closing it ends all its sessions. A wait always begins now, also a second one after the first ran out. */
export function setChoice(state: SimState, agent: AgentId, choice: Choice): SimState {
  const others = state.sessions.filter((run) => run.agent !== agent);
  if (choice === "closed") {
    return { ...state, sessions: others, idleExtra: { ...state.idleExtra, [agent]: 0 } };
  }
  const mine = state.sessions.filter((run) => run.agent === agent);
  const old = mine[0];
  const { now } = state;
  const waitRanOut = choice === "waiting" && old !== undefined && cause(old, "agentWorking", now) !== "waitingForUser";
  if (old !== undefined && mine.length === 1 && verdict(old) === choice && !old.command && !waitRanOut) {
    return state;
  }
  const was = old === undefined ? null : verdict(old);
  const next: Session = {
    key: old?.key ?? `${agent}-main`,
    agent,
    name: old?.name ?? AGENTS.find((entry) => entry.id === agent)?.folder ?? agent,
    state: choice,
    command: false,
    since: now,
    before: was,
    lastWorkingAt: mine.some((run) => verdict(run) === "working") ? now : (old?.lastWorkingAt ?? null),
    waitingSince: choice === "waiting" ? now : null,
  };
  // The agent keeps its place in the list.
  const at = state.sessions.findIndex((run) => run.agent === agent);
  const sessions =
    at < 0 ? [...others, next] : state.sessions.flatMap((run, index) => (run.agent !== agent ? [run] : index === at ? [next] : []));
  return { ...state, sessions };
}

export function setMode(state: SimState, mode: Mode): SimState {
  return { ...state, mode };
}

/** `PauseSwitch.set` and `TimedModes.switchedOff`: the switch ends a pause, and off also ends "stay reachable". */
export function setEnabled(state: SimState, enabled: boolean): SimState {
  return { ...state, enabled, pausedUntil: null, reachableUntil: enabled ? state.reachableUntil : null };
}

/** `Pause.deadline`: "until tomorrow" is the next 06:00, or 8 hours when that is less than 4 hours away. */
export function pauseLength(choice: PauseChoice, now: number): number {
  switch (choice) {
    case "thirtyMinutes":
      return 30 * 60;
    case "oneHour":
      return 3600;
    case "untilTomorrow": {
      const morning = (6 * 3600 - timeOfDay(now) + 86400) % 86400 || 86400;
      return morning >= 4 * 3600 ? morning : 8 * 3600;
    }
  }
}

/** `TimedModes.startPause`: a pause ends "stay reachable". */
export function startPause(state: SimState, choice: PauseChoice): SimState {
  return { ...state, pausedUntil: state.now + pauseLength(choice, state.now), reachableUntil: null };
}

export function resume(state: SimState): SimState {
  return { ...state, pausedUntil: null };
}

/** `TimedModes.startReachable`: "stay reachable" ends a pause. */
export function startReachable(state: SimState, choice: ReachableChoice): SimState {
  const hours = REACHABLES.find((entry) => entry.choice === choice)?.hours ?? 1;
  return { ...state, pausedUntil: null, reachableUntil: state.now + hours * 3600 };
}

export function stopReachable(state: SimState): SimState {
  return { ...state, reachableUntil: null };
}

/** `Pause.isPaused`, and `Reachable.isOn`: over when the time has come. */
function pausedUntil(state: SimState): number | null {
  return state.pausedUntil !== null && state.now < state.pausedUntil ? state.pausedUntil : null;
}

function reachableUntil(state: SimState): number | null {
  return state.reachableUntil !== null && state.now < state.reachableUntil ? state.reachableUntil : null;
}

export function setPower(state: SimState, power: Power): SimState {
  return withSafety({ ...state, power });
}

export function setLid(state: SimState, lid: Lid): SimState {
  return { ...state, lid };
}

export function setBattery(state: SimState, battery: number): SimState {
  return withSafety({ ...state, battery });
}

export function allowHelper(state: SimState): SimState {
  return { ...state, helper: true };
}

export function dismissHint(state: SimState): SimState {
  return { ...state, hintDismissed: true };
}

export function advance(state: SimState, ms: number): SimState {
  return { ...state, now: state.now + (SPEED * ms) / 1000 };
}

// MARK: Safety

/** `SafetyMonitor.evaluate`, for the battery: the stop begins at the floor and ends a few points above it. */
export function batteryStop(percent: number, onBattery: boolean, stopped: boolean): boolean {
  if (!onBattery) return false;
  return stopped ? percent < BATTERY_FLOOR + BATTERY_RECOVERY : percent <= BATTERY_FLOOR;
}

/** `TimedModes.safetyStopped`: a safety stop ends "stay reachable" for good. */
function withSafety(state: SimState): SimState {
  const batteryStopped = batteryStop(state.battery, state.power === "battery", state.batteryStopped);
  return { ...state, batteryStopped, reachableUntil: batteryStopped ? null : state.reachableUntil };
}

// MARK: Hold

export type HoldCause = "working" | "waitingForUser" | "finishedRecently" | "open";

/** `HoldPolicy.cause`: why one session keeps the Mac awake, or null when it does not. */
export function cause(run: Session, mode: Mode, now: number): HoldCause | null {
  const counts = verdict(run);
  if (counts === "working") return "working";
  if (counts === "waiting" && run.waitingSince !== null && now - run.waitingSince < WAITING_HOLD) return "waitingForUser";
  if (run.lastWorkingAt !== null && now - run.lastWorkingAt < RELEASE_AFTER) return "finishedRecently";
  return mode === "agentOpen" ? "open" : null;
}

export type Subject = { one: string } | { many: number };

export type Headline =
  | { kind: "working" | "waitingHeld" | "finishedRecently" | "open" | "idle" | "waitingReleased"; subject: Subject }
  | { kind: "alwaysOn" | "noAgents" | "switchedOff" }
  | { kind: "paused" | "reachable"; until: number }
  | { kind: "safetyStop"; percent: number };

function subject(names: readonly string[]): Subject | null {
  if (names.length === 0) return null;
  return names.length === 1 ? { one: names[0] } : { many: names.length };
}

function agentName(agent: AgentId): string {
  return AGENTS.find((entry) => entry.id === agent)?.name ?? agent;
}

/** `HoldPolicy.decide`: safety first, then the switch, then a pause, then the mode and the agents, then "stay reachable". */
export function headline(state: SimState): Headline {
  if (state.batteryStopped) return { kind: "safetyStop", percent: state.battery };
  if (!state.enabled) return { kind: "switchedOff" };
  const paused = pausedUntil(state);
  if (paused !== null) return { kind: "paused", until: paused };
  if (state.mode === "always") return { kind: "alwaysOn" };
  const held = state.sessions.map((run) => ({ name: agentName(run.agent), cause: cause(run, state.mode, state.now) }));
  for (const kind of ["working", "waitingForUser", "finishedRecently"] as const) {
    const found = subject(held.filter((entry) => entry.cause === kind).map((entry) => entry.name));
    if (found !== null) return { kind: kind === "waitingForUser" ? "waitingHeld" : kind, subject: found };
  }
  // An idle session that is only counted is open too.
  const extra = AGENTS.flatMap((agent) => Array.from({ length: state.idleExtra[agent.id] }, () => agent.name));
  const all = [...state.sessions.map((run) => agentName(run.agent)), ...extra];
  const everyone = subject(all);
  if (everyone !== null && state.mode === "agentOpen") return { kind: "open", subject: everyone };
  const reachable = reachableUntil(state);
  if (reachable !== null) return { kind: "reachable", until: reachable };
  if (everyone === null) return { kind: "noAgents" };
  const waiting = subject(state.sessions.filter((run) => verdict(run) === "waiting").map((run) => agentName(run.agent)));
  return waiting === null ? { kind: "idle", subject: everyone } : { kind: "waitingReleased", subject: waiting };
}

/** `HoldHeadline.keepsAwake`. */
export function keepsAwake(line: Headline): boolean {
  switch (line.kind) {
    case "working":
    case "waitingHeld":
    case "finishedRecently":
    case "open":
    case "alwaysOn":
    case "reachable":
      return true;
    default:
      return false;
  }
}

/** Simulated seconds until the last waiting hold runs out, or null when no agent holds by waiting. */
export function waitingLeft(state: SimState): number | null {
  const left = state.sessions
    .filter((run) => cause(run, state.mode, state.now) === "waitingForUser" && run.waitingSince !== null)
    .map((run) => (run.waitingSince ?? 0) + WAITING_HOLD - state.now);
  return left.length === 0 ? null : Math.max(...left);
}

/** How often, in real milliseconds, the clock must tick for the view to stay true, or null when nothing changes. */
export function tickEvery(state: SimState): number | null {
  const timed = pausedUntil(state) !== null || reachableUntil(state) !== null;
  if (state.sessions.length === 0) return timed ? 1000 : null;
  const pending = state.sessions.some((run) => {
    const why = cause(run, state.mode, state.now);
    return why === "waitingForUser" || why === "finishedRecently";
  });
  return pending ? 250 : 1000;
}

// MARK: Words

/** `PanelText.percent`: "88%", for a line on the screen. A label for a screen reader spells "percent" out. */
export function percent(value: number): string {
  return `${value}%`;
}

/** `HumaneDuration.counted`. */
function counted(count: number, noun: string): string {
  return count === 1 ? `1 ${noun}` : `${count} ${noun}s`;
}

/**
 * `HumaneDuration.lasting`: "for 12 minutes", "for 1 hour 22 minutes" up to
 * 10 hours, then "for 13 hours", then "for 3 days", or null under a minute.
 */
export function lasting(seconds: number): string | null {
  const minutes = Math.floor(Math.max(0, seconds) / 60);
  if (minutes < 1) return null;
  if (minutes < 60) return `for ${counted(minutes, "minute")}`;
  const hours = Math.floor(minutes / 60);
  if (hours < 10) {
    const rest = minutes % 60;
    return `for ${rest === 0 ? counted(hours, "hour") : `${counted(hours, "hour")} ${counted(rest, "minute")}`}`;
  }
  return `for ${hours < 48 ? counted(hours, "hour") : counted(Math.floor(hours / 24), "day")}`;
}

/** Seconds into the day at the simulated time `at`. */
function timeOfDay(at: number): number {
  return (((CLOCK + at) % 86400) + 86400) % 86400;
}

/** `PanelText.time`, on a 24 hour clock: the time of day at the simulated time `at`, as "15:30". */
export function clockTime(at: number): string {
  const minutes = Math.floor(timeOfDay(at) / 60);
  return `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
}

function phrase(who: Subject, one: string, many: string): string {
  return "one" in who ? `${who.one} ${one}` : `${who.many} agents ${many}`;
}

/** The minutes the menu names for a waiting hold: whole, and never less than one. */
export function minutesLeft(seconds: number): number {
  return Math.max(1, Math.ceil(seconds / 60));
}

/** `PanelText.headline`: the outcome, then the reason. */
export function headlineText(line: Headline, waitingFor: number | null, now = 0): { title: string; subtitle: string } {
  const awake = "Your Mac stays awake";
  const canSleep = "Your Mac can sleep";
  switch (line.kind) {
    case "working":
      return { title: awake, subtitle: phrase(line.subject, "is working", "are working") };
    case "waitingHeld": {
      const waiting = phrase(line.subject, "is waiting for you", "are waiting for you");
      return {
        title: awake,
        subtitle: waitingFor === null ? waiting : `${waiting}, can sleep in ${counted(minutesLeft(waitingFor), "minute")}`,
      };
    }
    case "finishedRecently":
      return { title: awake, subtitle: phrase(line.subject, "finished a moment ago", "finished a moment ago") };
    case "open":
      return { title: awake, subtitle: phrase(line.subject, "is open", "are open") };
    case "alwaysOn":
      return { title: awake, subtitle: "Until you turn it off" };
    case "idle":
      return { title: canSleep, subtitle: "one" in line.subject ? `${line.subject.one} is idle` : "All agents are idle" };
    case "waitingReleased":
      return { title: canSleep, subtitle: phrase(line.subject, "is waiting for you", "are waiting for you") };
    case "noAgents":
      return { title: canSleep, subtitle: "No agent is open" };
    case "safetyStop":
      return { title: "agent caffeine has stopped", subtitle: `The battery is at ${percent(line.percent)}` };
    case "switchedOff":
      return { title: "agent caffeine is off", subtitle: "Your Mac sleeps as usual" };
    case "paused": {
      // `PanelText.startsAgain`: a pause never ends later than tomorrow.
      const today = timeOfDay(now) + (line.until - now) < 86400;
      return { title: "agent caffeine is paused", subtitle: `Starts again ${today ? "" : "tomorrow "}at ${clockTime(line.until)}` };
    }
    case "reachable":
      return { title: awake, subtitle: `Reachable until ${clockTime(line.until)}` };
  }
}

/** `PanelText.working`, `waiting` and `idle`: the phrase of one session. */
function detailOf(run: Session, now: number): string {
  const time = lasting(now - run.since);
  const startSeen = run.before !== null;
  switch (verdict(run)) {
    case "working":
      if (run.command) return ["Running 1 command", time].filter(Boolean).join(" ");
      if (time !== null) return `Working ${time}`;
      return startSeen ? "Started a moment ago" : "Working";
    case "waiting":
      if (time !== null) return `Waiting for your answer ${time}`;
      return startSeen ? "Asked you a moment ago" : "Waiting for your answer";
    case "idle":
      if (time !== null) return `Idle ${time}`;
      return run.before === "working" ? "Finished a moment ago" : "Idle";
  }
}

/** `PanelText.groupSummary`. */
function groupSummary(working: number, waiting: number, idle: number): string {
  const active = [working > 0 ? `${working} working` : null, waiting > 0 ? `${waiting} waiting for you` : null].filter(Boolean);
  return active.length === 0 ? counted(idle, "idle session") : active.join(", ");
}

// MARK: Rows

export type Child = { key: string; label: string; detail: string | null };

export type Group = {
  agent: AgentId;
  icon: AgentIconName;
  title: string;
  /** The most urgent state inside, for the ring. */
  state: WorkState;
  detail: string;
  /** The detail below the title, or at the trailing edge. */
  place: "below" | "trailing";
  /** Null for a line that does not open. */
  open: boolean | null;
  children: readonly Child[];
  layout: "oneLine" | "twoLines";
};

/** The widths the app measures, as characters: what fits next to an agent's name, and a session next to its state. */
const SUMMARY_FIT = 30;
const CHILD_FIT = 38;

const RANK: Record<WorkState, number> = { waiting: 0, working: 1, idle: 2 };

/** `MenuModel.groups`: one group for each agent. Waiting first, then working, the longest on top, then idle, the last active on top. */
export function groups(state: SimState): Group[] {
  const { now } = state;
  const built = AGENTS.flatMap((agent) => {
    const mine = state.sessions.filter((run) => run.agent === agent.id);
    const extra = state.idleExtra[agent.id];
    if (mine.length + extra === 0) return [];
    const oldestFirst = (a: Session, b: Session) => a.since - b.since;
    const waiting = mine.filter((run) => verdict(run) === "waiting").sort(oldestFirst);
    const working = mine.filter((run) => verdict(run) === "working").sort(oldestFirst);
    const idle = mine.filter((run) => verdict(run) === "idle").sort((a, b) => b.since - a.since);
    const active = [...waiting, ...working];
    const ring: WorkState = waiting.length > 0 ? "waiting" : working.length > 0 ? "working" : "idle";
    const since = (active[0] ?? idle[0])?.since ?? 0;
    const head = { agent: agent.id, icon: agent.icon, state: ring };
    if (mine.length === 1 && extra === 0) {
      const only = mine[0];
      const group: Group = {
        ...head,
        title: active.length > 0 ? `${agent.name} · ${only.name}` : agent.name,
        detail: detailOf(only, now),
        place: active.length > 0 ? "below" : "trailing",
        open: null,
        children: [],
        layout: "oneLine",
      };
      return [{ group, since }];
    }
    const idleCount = idle.length + extra;
    const detail = groupSummary(working.length, waiting.length, idleCount);
    const children: Child[] = active.map((run) => ({ key: run.key, label: run.name, detail: detailOf(run, now) }));
    if (active.length > 0 && idleCount > 0) {
      children.push({ key: "idle", label: counted(idleCount, "idle session"), detail: null });
    }
    const group: Group = {
      ...head,
      title: agent.name,
      detail,
      place: agent.name.length + detail.length <= SUMMARY_FIT ? "trailing" : "below",
      // A group with work in it starts open, an idle one closed.
      open: active.length > 0,
      children,
      layout: children.every((child) => child.detail === null || child.label.length + child.detail.length <= CHILD_FIT)
        ? "oneLine"
        : "twoLines",
    };
    return [{ group, since }];
  });
  return built
    .map((entry, index) => ({ ...entry, index }))
    .sort((a, b) => {
      const rank = RANK[a.group.state] - RANK[b.group.state];
      if (rank !== 0) return rank;
      const time = a.group.state === "idle" ? b.since - a.since : a.since - b.since;
      return time !== 0 ? time : a.index - b.index;
    })
    .map((entry) => entry.group);
}

// MARK: Robot

/** `HeroPose`. */
export type Pose = "awake" | "reachable" | "attentive" | "asleep" | "paused" | "off" | "trouble";

/** `MenuModel.pose(for:)`. */
export function pose(line: Headline): Pose {
  switch (line.kind) {
    case "working":
    case "finishedRecently":
    case "open":
    case "alwaysOn":
      return "awake";
    case "waitingHeld":
      return "attentive";
    case "idle":
    case "waitingReleased":
    case "noAgents":
      return "asleep";
    case "safetyStop":
      return "trouble";
    case "switchedOff":
      return "off";
    case "paused":
      return "paused";
    case "reachable":
      return "reachable";
  }
}

/** `MenuBarLook`: what the robot in the menu bar is drawn from. */
export type IconLook = { eyes: "happy" | "open" | "closed" | "dead"; solid: boolean; opacity: number; paused?: boolean };

export function iconLook(of: Pose): IconLook {
  switch (of) {
    case "awake":
    case "reachable":
      return { eyes: "happy", solid: true, opacity: 1 };
    case "attentive":
      return { eyes: "open", solid: true, opacity: 1 };
    case "asleep":
      return { eyes: "closed", solid: false, opacity: 1 };
    case "paused":
      return { eyes: "closed", solid: false, opacity: 0.45, paused: true };
    case "off":
      return { eyes: "closed", solid: false, opacity: 0.45 };
    case "trouble":
      return { eyes: "dead", solid: false, opacity: 1 };
  }
}

/** `MenuBarLook.accessibilityLabel`, and `PanelText.menuBarReachable` when the Mac stays reachable until `reachable`. */
export function iconLabel(look: IconLook, reachable: number | null = null): string {
  switch (look.eyes) {
    case "happy":
      return reachable === null ? "agent caffeine: your Mac stays awake" : `agent caffeine: reachable until ${clockTime(reachable)}`;
    case "open":
      return "agent caffeine: an agent is waiting for you";
    case "closed":
      if (look.paused === true) return "agent caffeine: paused";
      return look.opacity < 1 ? "agent caffeine: off" : "agent caffeine: your Mac can sleep";
    case "dead":
      return "agent caffeine: needs attention";
  }
}

// MARK: View

/** `PanelAttention`: the one line below the headline that needs the reader. */
export type Attention = { kind: "safetyStop" | "reachableNeedsLidClosed" | "lidClosedNotSetUp"; text: string };

/** `PanelBattery`: the charge and the level where agent caffeine lets the Mac sleep, on one line below the headline. */
export type Battery = {
  percent: number;
  floor: number;
  level: "normal" | "nearFloor" | "stopped";
  /** "88%". Null when stopped: the headline says the number then. */
  charge: string | null;
  /** What follows from it, after the number. */
  consequence: string;
  /** For a screen reader. */
  spoken: string;
};

/** `BottomBar`: what stands in place of the mode, and what the timer button offers. */
export type Bar = {
  /** "Paused until 15:30", with "Resume" after it. */
  pausedLabel: string | null;
  /** "Reachable until 18:30", with "Stop" after it. */
  reachableLabel: string | null;
  /** The timer button is there: not while off, paused or reachable. */
  timer: boolean;
  /** The choices of "stay reachable" are offered: not after a safety stop. */
  reachable: boolean;
  /** Below the choices of "stay reachable", on battery. */
  reachableCost: string | null;
};

export type View = {
  /** The app keeps the Mac awake. */
  held: boolean;
  pose: Pose;
  look: IconLook;
  title: string;
  subtitle: string;
  /** What a screen reader says for the icon in the menu bar. */
  iconLabel: string;
  attention: Attention | null;
  /** Null on power, and while agent caffeine is off or paused. */
  battery: Battery | null;
  bar: Bar;
  /** The time on the menu bar's clock, as "9:41". */
  clock: string;
  groups: readonly Group[];
  /** In place of the list when no agent is open. */
  emptyText: string | null;
};

/** `MenuModel.attention`, for the three lines the simulator can reach. */
function attention(state: SimState, line: Headline): Attention | null {
  // The line of the battery says when it starts again. Once is enough.
  if (line.kind === "safetyStop" && battery(state, line) === null) {
    return { kind: "safetyStop", text: `agent caffeine starts again at ${percent(BATTERY_FLOOR + BATTERY_RECOVERY)}` };
  }
  if (reachableUntil(state) !== null && line.kind !== "paused" && line.kind !== "switchedOff" && state.power === "battery" && !state.helper) {
    return { kind: "reachableNeedsLidClosed", text: "Close the lid and your Mac still sleeps. Set up the helper to stay reachable." };
  }
  if (state.power === "battery" && !state.helper && !state.hintDismissed) {
    return { kind: "lidClosedNotSetUp", text: "Your Mac still sleeps with the lid closed on battery" };
  }
  return null;
}

/** `MenuModel.battery`: only on battery, and while agent caffeine could keep the Mac awake. */
function battery(state: SimState, line: Headline): Battery | null {
  if (state.power !== "battery" || line.kind === "switchedOff" || line.kind === "paused") return null;
  const shown = Math.min(Math.max(state.battery, 0), 100);
  const level = line.kind === "safetyStop" ? "stopped" : shown <= BATTERY_FLOOR + BATTERY_WARNING ? "nearFloor" : "normal";
  const recovery = BATTERY_FLOOR + BATTERY_RECOVERY;
  return {
    percent: shown,
    floor: BATTERY_FLOOR,
    level,
    charge: level === "stopped" ? null : percent(shown),
    // The app stops at the floor, and its line is changing from "sleeps below" to "sleeps at".
    consequence: level === "stopped" ? `starts again at ${percent(recovery)}` : `sleeps at ${percent(BATTERY_FLOOR)}`,
    spoken:
      level === "stopped"
        ? `Battery ${shown} percent, agent caffeine starts again at ${recovery} percent`
        : `Battery ${shown} percent, agent caffeine lets your Mac sleep at ${BATTERY_FLOOR} percent`,
  };
}

/** `MenuModel.reachableLabel` and `canStayReachable`, and the rules of `BottomBar`. */
function bar(state: SimState, line: Headline): Bar {
  const paused = line.kind === "paused" ? `Paused until ${clockTime(line.until)}` : null;
  const until = state.enabled && line.kind !== "paused" ? reachableUntil(state) : null;
  const reachable = until === null ? null : `Reachable until ${clockTime(until)}`;
  return {
    pausedLabel: paused,
    reachableLabel: reachable,
    timer: state.enabled && paused === null && reachable === null,
    reachable: state.enabled && line.kind !== "safetyStop",
    reachableCost: state.power === "battery" ? `Uses about ${percent(REACHABLE_COST)} of battery per hour` : null,
  };
}

export function view(state: SimState): View {
  const line = headline(state);
  const waitingFor = line.kind === "waitingHeld" ? waitingLeft(state) : null;
  const stance = pose(line);
  const empty = state.sessions.length === 0 && AGENTS.every((agent) => state.idleExtra[agent.id] === 0);
  return {
    held: keepsAwake(line),
    pose: stance,
    look: iconLook(stance),
    iconLabel: iconLabel(iconLook(stance), line.kind === "reachable" ? line.until : null),
    ...headlineText(line, waitingFor, state.now),
    attention: attention(state, line),
    battery: battery(state, line),
    bar: bar(state, line),
    clock: clockTime(state.now).replace(/^0/, ""),
    groups: groups(state),
    // `PanelText.empty`: the invitation only when a new agent is all that is missing.
    emptyText: !empty
      ? null
      : line.kind === "noAgents"
        ? "Start an agent and agent caffeine keeps your Mac awake while it works"
        : "No agent is open",
  };
}
