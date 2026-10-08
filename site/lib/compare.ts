import { agentsMoreThan } from "@/lib/agents";
import { PRICE_LIST } from "@/lib/pricing";
import { BATTERY_FLOOR } from "@/lib/simulator";

/** The day every cell about another tool was read on that tool's own page. */
export const CHECKED_ON = "2026-10-08";

export type ToolId = "ours" | "adrafinil" | "holdmylid" | "lidrun" | "clamshell" | "amphetamine";

export type Tool = {
  id: ToolId;
  name: string;
  /** The tool's own pages that its cells were read from. Ours has none: its cells come from this site. */
  sources: readonly { label: string; url: string }[];
};

/**
 * `unstated` is for what the tool's own pages do not say. It never means no:
 * `no` is only for what the maker says the tool does not do.
 */
export type Value = "yes" | "no" | "partly" | "unstated";

/** A value with a few words, or `text` alone for a row of words (a price, a date, a list). */
export type Cell = { value: Value; note?: string } | { text: string; note?: string };

export type Row = {
  id: string;
  label: string;
  /** A row where yes is not the better answer: its values are written as words, with no mark. */
  words?: boolean;
  cells: Record<ToolId, Cell>;
};

export const TOOLS: readonly Tool[] = [
  { id: "ours", name: "Agent Caffeine", sources: [] },
  {
    id: "adrafinil",
    name: "Adrafinil",
    sources: [
      { label: "README", url: "https://github.com/kageroumado/adrafinil" },
      { label: "site", url: "https://kagerou.glass/adrafinil/" },
      { label: "releases", url: "https://github.com/kageroumado/adrafinil/releases" },
    ],
  },
  {
    id: "holdmylid",
    name: "Hold My Lid",
    sources: [
      { label: "site", url: "https://holdmylid.app/" },
      { label: "guide", url: "https://holdmylid.app/blog/keep-mac-awake-ai-coding-agents" },
    ],
  },
  {
    id: "lidrun",
    name: "LidRun",
    sources: [
      { label: "site", url: "https://lidrun.com/" },
      { label: "pricing", url: "https://lidrun.com/pricing" },
      { label: "changelog", url: "https://lidrun.com/changelog" },
      { label: "article", url: "https://lidrun.com/blog/safe-alternative-to-pmset-disablesleep" },
    ],
  },
  {
    id: "clamshell",
    name: "Clamshell",
    sources: [
      { label: "site", url: "https://clamshell.dev/" },
      { label: "guide", url: "https://clamshell.dev/guides/lidrun-vs-amphetamine-vs-clamshell" },
    ],
  },
  {
    id: "amphetamine",
    name: "Amphetamine",
    sources: [{ label: "Mac App Store", url: "https://apps.apple.com/us/app/amphetamine/id937984704" }],
  },
];

export const OURS: ToolId = "ours";

const yes = (note?: string): Cell => ({ value: "yes", note });
const no = (note?: string): Cell => ({ value: "no", note });
const partly = (note: string): Cell => ({ value: "partly", note });
const unstated = (note?: string): Cell => ({ value: "unstated", note });
const text = (words: string, note?: string): Cell => ({ text: words, note });

/** The rows in the order a buyer asks: the price first, then the lid, the agents, the stops and the notifications. */
export const ROWS: readonly Row[] = [
  {
    id: "price",
    label: "Price, paid once",
    cells: {
      ours: text(PRICE_LIST, "7-day free trial. Closed source"),
      adrafinil: text("Free", "Open source (MIT)"),
      holdmylid: text("$9.99 for 3 Macs", "Early price, then $14.99. Free trial"),
      lidrun: text("Free with the lid open", "Lid closed: a few free runs, then $9.90 for 1 Mac, $19.90 for 3 Macs"),
      clamshell: text("$9.99 for 1 Mac, $19.99 for 3 Macs", "7-day free trial"),
      amphetamine: text("Free", "Mac App Store"),
    },
  },
  {
    id: "lid-battery",
    label: "Lid closed on battery",
    cells: {
      ours: yes(),
      adrafinil: partly("On battery: not stated"),
      holdmylid: yes("Not in every case, its page says"),
      lidrun: yes("A few free runs, then the paid plan"),
      clamshell: yes(),
      amphetamine: partly("On battery: not stated"),
    },
  },
  {
    id: "helper",
    label: "Needs an admin helper",
    words: true,
    cells: {
      ours: yes("Only for battery, allowed once"),
      adrafinil: yes("Admin rights once"),
      holdmylid: unstated(),
      lidrun: yes("Once, or a password each time"),
      clamshell: no(),
      amphetamine: partly("An optional script"),
    },
  },
  {
    id: "works",
    label: "Knows when an agent works",
    cells: {
      ours: yes(`Agent's own state: 6 agents. Signs of work: more than ${agentsMoreThan} agents`),
      adrafinil: yes("Agent's own state: 9 agents"),
      holdmylid: yes("Agent's own state: 3 to 7 agents, its page gives both. Process check: others"),
      lidrun: partly("Process check"),
      clamshell: no("You arm it yourself"),
      amphetamine: partly("While an app you pick runs"),
    },
  },
  {
    id: "waits",
    label: "Knows when an agent waits",
    cells: {
      ours: yes(),
      adrafinil: yes("Claude Code"),
      holdmylid: unstated(),
      lidrun: partly("An alert"),
      clamshell: no(),
      amphetamine: unstated(),
    },
  },
  {
    id: "sleeps",
    label: "Sleeps when the work is done",
    cells: {
      ours: yes(),
      adrafinil: yes(),
      holdmylid: yes(),
      lidrun: yes(),
      clamshell: partly("A script can disarm it"),
      amphetamine: partly("When the app quits"),
    },
  },
  {
    id: "battery-stop",
    label: "Stops at a low battery",
    cells: {
      ours: yes(`At ${BATTERY_FLOOR}%, adjustable`),
      adrafinil: yes("Level not stated"),
      holdmylid: yes("Adjustable"),
      lidrun: yes("Adjustable"),
      clamshell: yes("Off by default"),
      amphetamine: yes(),
    },
  },
  {
    id: "heat-stop",
    label: "Stops when the Mac is too hot",
    cells: {
      ours: yes(),
      adrafinil: yes("Lid closed"),
      holdmylid: unstated(),
      lidrun: yes(),
      clamshell: yes("Always on"),
      amphetamine: unstated(),
    },
  },
  {
    id: "notifies",
    label: "Notifies when an agent finishes or waits",
    cells: {
      ours: yes("Both"),
      adrafinil: partly("A chime, and a summary later"),
      holdmylid: partly("When agents finish"),
      lidrun: partly("When an agent may wait"),
      clamshell: unstated(),
      amphetamine: unstated(),
    },
  },
  {
    id: "click",
    label: "Notification click opens the agent",
    cells: {
      ours: yes(),
      adrafinil: unstated(),
      holdmylid: unstated(),
      lidrun: unstated(),
      clamshell: unstated(),
      amphetamine: unstated(),
    },
  },
  {
    id: "dims",
    label: "Display dims as the lid closes",
    cells: {
      ours: yes("With a lid angle sensor"),
      adrafinil: partly("Off at lid close"),
      holdmylid: partly("Off at lid close"),
      lidrun: unstated(),
      clamshell: partly("Off at lid close"),
      amphetamine: partly("Off at lid close"),
    },
  },
  {
    id: "cli",
    label: "Command line tool",
    cells: {
      ours: yes(),
      adrafinil: yes(),
      holdmylid: unstated(),
      lidrun: yes("An agent can drive it from the terminal"),
      clamshell: partly("A URL scheme for scripts"),
      amphetamine: partly("AppleScript"),
    },
  },
  {
    id: "mcp",
    label: "MCP server",
    cells: {
      ours: yes(),
      adrafinil: yes(),
      holdmylid: unstated(),
      lidrun: unstated(),
      clamshell: unstated(),
      amphetamine: unstated(),
    },
  },
  {
    id: "intel",
    label: "Runs on Intel Macs",
    cells: {
      ours: yes(),
      adrafinil: unstated(),
      holdmylid: yes(),
      lidrun: yes(),
      clamshell: no("Apple silicon only"),
      amphetamine: yes("macOS 10.13 or later"),
    },
  },
  {
    id: "updated",
    label: "Last update",
    cells: {
      ours: text("October 7, 2026"),
      adrafinil: text("October 7, 2026"),
      holdmylid: unstated(),
      lidrun: text("September 27, 2026"),
      clamshell: text("October 5, 2026"),
      amphetamine: text("November 10, 2023"),
    },
  },
  {
    id: "also",
    label: "Also has",
    cells: {
      ours: text("Stay reachable from your phone"),
      adrafinil: text("MCP tool and command for agents"),
      holdmylid: text("Plugged-in only mode"),
      lidrun: text("Webhooks, command runner"),
      clamshell: text("Shortcuts, lock at lid open"),
      amphetamine: text("Many triggers"),
    },
  },
];

export function isText(cell: Cell): cell is { text: string; note?: string } {
  return "text" in cell;
}
