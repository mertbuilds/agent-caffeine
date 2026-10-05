import type { AgentIconName } from "@/components/agent-icons";

/**
 * A model of the app's decisions, mirrored from the Swift source:
 * `AwakeMode.shouldHold` (Models/AgentState.swift), the status line, rows and
 * battery row (UI/MenuBarView.swift), the work grace period
 * (Detectors/ProcessWatcher.swift) and the Claude Code session window
 * (Detectors/ClaudeCodeWatcher.swift). Times are in simulated seconds. Unlike
 * the app, an idle Claude Code session stays listed.
 */

export type Mode = "always" | "agentOpen" | "agentWorking";
export type Power = "adapter" | "battery";
export type AgentId = "claude" | "codex" | "opencode";
export type AgentState = "active" | "waitingForInput";

export type Run = { id: AgentId; working: boolean; lastWork: number };

export type SimState = {
  enabled: boolean;
  mode: Mode;
  power: Power;
  overrideInstalled: boolean;
  runs: readonly Run[];
  now: number;
};

export const MODES: readonly { mode: Mode; title: string; explanation: string }[] = [
  { mode: "always", title: "Always", explanation: "Awake until you switch it off" },
  { mode: "agentOpen", title: "While an agent is open", explanation: "Awake while an agent is running, also at its prompt" },
  { mode: "agentWorking", title: "While an agent is working", explanation: "Awake only while an agent does work" },
];

export const AGENTS: readonly { id: AgentId; name: string; process: string; icon: AgentIconName }[] = [
  { id: "claude", name: "Claude Code", process: "claude", icon: "claudecode" },
  { id: "codex", name: "Codex", process: "codex", icon: "codex" },
  { id: "opencode", name: "opencode", process: "opencode", icon: "opencode" },
];

/** `ProcessWatcher.workGracePeriod`. */
export const GRACE = 120;
/** `ClaudeCodeWatcher.activeWindow`. */
const SESSION_ACTIVE = 5;
const SESSION_LABEL = "website · Fix flaky checkout test";
/** Simulated seconds per real second, so the grace period runs out in five seconds. */
export const SPEED = 24;
/** Past an hour the panel's times change once an hour, too slowly to keep a timer for. */
const AGO_LIMIT = 3600;

export type Row = {
  key: string;
  label: string;
  sub: string;
  state: AgentState;
  time: string;
  lastActivity: number;
};

export type Battery = "none" | "lidWillSleep" | "overrideActive";

export type View = {
  held: boolean;
  status: string;
  rows: readonly Row[];
  battery: Battery;
  outcome: { title: string; reason: string; hint: string };
};

export type PresetId = "working" | "waiting" | "nothing" | "always" | "battery";

export const PRESETS: readonly { id: PresetId; title: string }[] = [
  { id: "working", title: "Agent working" },
  { id: "waiting", title: "Agents idle" },
  { id: "always", title: "Always on" },
  { id: "nothing", title: "Nothing running" },
  { id: "battery", title: "On battery" },
];

export const INITIAL: SimState = preset({ enabled: true, mode: "agentWorking", power: "adapter", overrideInstalled: false, runs: [], now: 0 }, "working");

/** Sets the whole state to a situation, keeping the clock. */
export function preset(state: SimState, id: PresetId): SimState {
  const now = state.now;
  const base: SimState = { enabled: true, mode: "agentWorking", power: "adapter", overrideInstalled: false, runs: [], now };
  const working: Run = { id: "claude", working: true, lastWork: now };
  switch (id) {
    case "working":
      return { ...base, runs: [working] };
    case "waiting":
      return {
        ...base,
        runs: [
          { id: "claude", working: false, lastWork: now - 140 },
          { id: "codex", working: false, lastWork: now - 170 },
        ],
      };
    case "nothing":
      return base;
    case "always":
      return { ...base, mode: "always" };
    case "battery":
      return { ...base, power: "battery", runs: [working] };
  }
}

/**
 * The examples that play until the reader first touches the simulator, each
 * held for `hold` real milliseconds. A step either sets a situation or lets an
 * agent go idle, so the grace period runs out on screen.
 */
export const DEMO: readonly { preset: PresetId; idle?: AgentId; hold: number }[] = [
  { preset: "working", hold: 4000 },
  { preset: "working", idle: "claude", hold: 9000 },
  { preset: "waiting", hold: 4000 },
  { preset: "nothing", hold: 4000 },
  { preset: "always", hold: 4000 },
  { preset: "battery", hold: 4000 },
];

export function demo(state: SimState, step: (typeof DEMO)[number]): SimState {
  return step.idle === undefined ? preset(state, step.preset) : setWorking(state, step.idle, false);
}

export function start(state: SimState, id: AgentId): SimState {
  if (state.runs.some((run) => run.id === id)) {
    return state;
  }
  // A process seen for the first time counts as working.
  return { ...state, runs: [...state.runs, { id, working: true, lastWork: state.now }] };
}

export function stop(state: SimState, id: AgentId): SimState {
  return { ...state, runs: state.runs.filter((run) => run.id !== id) };
}

export function setWorking(state: SimState, id: AgentId, working: boolean): SimState {
  return {
    ...state,
    runs: state.runs.map((run) =>
      run.id !== id || run.working === working ? run : { id, working, lastWork: state.now },
    ),
  };
}

export function advance(state: SimState, ms: number): SimState {
  return { ...state, now: state.now + (SPEED * ms) / 1000 };
}

/** Simulated seconds since the agent last worked, 0 while it works. */
function idleFor(run: Run, now: number): number {
  return run.working ? 0 : now - run.lastWork;
}

/** The share of the grace period still left, from 1 to 0, or null while working. */
export function graceLeft(run: Run, now: number): number | null {
  return run.working ? null : Math.max(0, 1 - idleFor(run, now) / GRACE);
}

/** How often, in real milliseconds, the clock must tick for the view to stay true, or null when nothing changes. */
export function tickEvery(state: SimState): number | null {
  const idle = state.runs.filter((run) => !run.working).map((run) => idleFor(run, state.now));
  if (idle.some((seconds) => seconds < GRACE)) {
    return 250;
  }
  return idle.some((seconds) => seconds < AGO_LIMIT) ? 1000 : null;
}

/** `MenuBarView.timeAgo`. */
function timeAgo(seconds: number): string {
  const s = Math.floor(seconds);
  if (s < 5) return "now";
  if (s < 60) return `${s}s`;
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  return `${Math.floor(s / 3600)}h`;
}

const STATE_NAMES: Record<AgentState, string> = { active: "Active", waitingForInput: "Waiting for input" };

function row(key: string, label: string, source: string, state: AgentState, lastActivity: number, now: number): Row {
  return { key, label, sub: `${source} · ${STATE_NAMES[state]}`, state, time: timeAgo(now - lastActivity), lastActivity };
}

function rows(state: SimState): Row[] {
  const { now } = state;
  const sessions: Row[] = [];
  const processes: Row[] = [];
  for (const agent of AGENTS) {
    const run = state.runs.find((candidate) => candidate.id === agent.id);
    if (run === undefined) {
      continue;
    }
    const idle = idleFor(run, now);
    const lastActivity = now - idle;
    if (agent.id === "claude") {
      // A session file is active only while it is being written; between turns it waits.
      const sessionState = idle < SESSION_ACTIVE ? "active" : "waitingForInput";
      sessions.push(row("session", SESSION_LABEL, "Claude Code", sessionState, lastActivity, now));
    }
    const processState = idle < GRACE ? "active" : "waitingForInput";
    processes.push(row(agent.id, agent.process, "CLI", processState, lastActivity, now));
  }
  return [...sessions, ...processes].sort((a, b) => b.lastActivity - a.lastActivity);
}

/** `AwakeMode.shouldHold`, for a licensed copy. */
function shouldHold(state: SimState, agents: readonly Row[]): boolean {
  if (!state.enabled) return false;
  switch (state.mode) {
    case "always":
      return true;
    case "agentOpen":
      return agents.length > 0;
    case "agentWorking":
      return agents.some((agent) => agent.state === "active");
  }
}

/** `MenuBarView.statusLine`. The simulated power assertion never fails, so held always equals shouldHold. */
function statusLine(state: SimState, held: boolean, agents: readonly Row[]): string {
  if (!state.enabled) return "Paused";
  if (held) return "Keeping the Mac awake";
  if (agents.length === 0) return "No agent is running. The Mac may sleep";
  return "Agents are idle. The Mac may sleep";
}

/** `MenuBarView.batteryRow`: once installed, the override is switched on whenever the Mac is held on battery. */
function battery(state: SimState, held: boolean): Battery {
  if (state.power !== "battery" || !held) return "none";
  return state.overrideInstalled ? "overrideActive" : "lidWillSleep";
}

function outcome(state: SimState, held: boolean, agents: readonly Row[], power: Battery): View["outcome"] {
  if (held) {
    const reason =
      state.mode === "always"
        ? "because the mode is Always"
        : agents.some((agent) => agent.state === "active")
          ? "because an agent is working"
          : "because an agent is open";
    const hint =
      power === "lidWillSleep"
        ? "Until you close the lid. On battery that sleeps it, unless the override is on"
        : power === "overrideActive"
          ? "Lid open or closed, on battery too"
          : "Lid open or closed";
    return { title: "Your Mac stays awake", reason, hint };
  }
  if (!state.enabled) {
    return { title: "Your Mac can sleep", reason: "because agent caffeine is paused", hint: "" };
  }
  if (agents.length === 0) {
    return { title: "Your Mac can sleep", reason: "because no agent is running", hint: "" };
  }
  return {
    title: "Your Mac can sleep",
    reason: "because every agent is idle",
    hint: state.mode === "agentWorking" ? "With “While an agent is open” it would stay awake" : "",
  };
}

export function view(state: SimState): View {
  const agents = rows(state);
  const held = shouldHold(state, agents);
  const power = battery(state, held);
  return {
    held,
    status: statusLine(state, held, agents),
    rows: agents,
    battery: power,
    outcome: outcome(state, held, agents, power),
  };
}

/** The app's menu bar icon description (`MenuBarIcon.accessibilityLabel`). */
export function iconLabel(held: boolean): string {
  return held ? "agent caffeine, keeping the Mac awake" : "agent caffeine, not keeping the Mac awake";
}
