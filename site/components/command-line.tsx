import type { ReactNode } from "react";
import { AgentIcon, type AgentIconName } from "@/components/agent-icons";
import { AgentMark, PanelSurface } from "@/components/agents-panel";
import { SectionHeading } from "@/components/section-heading";

/** Still cuts of a terminal and of the app, with the words of `PanelText.swift` (the line of a hold, "Set up for agents") and of the command line tool. */
const MUTED = "text-[var(--panel-muted)]";

/** The agents with a mark that "Set up for agents" writes the skill for (`SkillCatalog.swift`). */
const SKILL_AGENTS: readonly { name: string; icon: AgentIconName }[] = [
  { name: "Claude Code", icon: "claudecode" },
  { name: "Codex", icon: "codex" },
  { name: "opencode", icon: "opencode" },
  { name: "Cursor", icon: "cursor" },
  { name: "Gemini CLI", icon: "geminicli" },
  { name: "Pi", icon: "pi" },
  { name: "Grok Build", icon: "grok" },
  { name: "Amp", icon: "amp" },
  { name: "goose", icon: "goose" },
  { name: "OpenClaw", icon: "openclaw" },
];

/** A Terminal window: the command after the prompt, then what it printed. */
function Terminal({ command, label, output }: { command: string; label: string; output: string }) {
  return (
    <div
      aria-label={label}
      className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-md border border-[var(--panel-line)] bg-bg"
      role="img"
    >
      <div aria-hidden="true" className="flex h-6 shrink-0 items-center gap-1.5 bg-[var(--panel)] px-2.5">
        <span className="size-2 rounded-full bg-[#ff5f57]" />
        <span className="size-2 rounded-full bg-[#febc2e]" />
        <span className="size-2 rounded-full bg-[#28c840]" />
      </div>
      <div aria-hidden="true" className="flex flex-col px-2.5 py-2 text-left font-mono text-[12px] leading-[18px]">
        <p className="break-words">
          <span className="text-muted">$ </span>
          {command}
        </p>
        <p className="break-words text-muted">{output}</p>
      </div>
    </div>
  );
}

/** The line of a hold in the menu (`MenuModel.holdGroups`): the terminal glyph, what asked, what it does, and "Stop". */
function HoldRow({ detail, label, title }: { detail: string; label: string; title: string }) {
  return (
    <PanelSurface className="panel-still flex shrink-0 items-center gap-2 rounded-md py-1.5 pl-[7px] pr-3" label={label}>
      <AgentMark icon={null} state="working" />
      <span className="flex min-w-0 flex-1 flex-col gap-px leading-4">
        <span className="truncate">{title}</span>
        <span className={`text-pretty text-[12px] tabular-nums ${MUTED}`}>{detail}</span>
      </span>
      <span aria-hidden="true" className="shrink-0 text-accent">
        Stop
      </span>
    </PanelSurface>
  );
}

/** Radius: the card 20px, less its 8px padding is the cut at 12px, less its 6px padding is each box inside at 6px. */
function Card({ children, text, title }: { children: ReactNode; text: string; title: string }) {
  return (
    <li className="flex flex-col rounded-[20px] border border-border p-2">
      <div className="flex h-52 flex-col gap-1.5 overflow-hidden rounded-xl bg-surface p-1.5">{children}</div>
      <div className="flex flex-col gap-1.5 px-2 pb-2 pt-4">
        <h3 className="text-balance font-medium leading-snug">{title}</h3>
        <p className="text-pretty text-sm leading-relaxed text-muted">{text}</p>
      </div>
    </li>
  );
}

export function CommandLine() {
  return (
    <section id="command-line" className="mx-auto flex w-full max-w-[1120px] scroll-mt-20 flex-col gap-10">
      <SectionHeading
        lead="A script, a render, a backup: one command keeps your Mac awake until the job ends"
        title="It works for any long job too"
      />
      <div className="flex flex-col gap-4">
        <ul className="mx-auto grid w-full max-w-[36rem] gap-4 lg:max-w-none lg:grid-cols-3">
          <Card
            text="Your Mac stays awake while the command runs, and can sleep when it ends. The exit code stays the same"
            title="Put it in front of a command"
          >
            <Terminal
              command="agent-caffeine hold -- npm run build"
              label="A terminal that runs agent-caffeine hold -- npm run build"
              output="> next build"
            />
            <HoldRow
              detail="Keeps your Mac awake while it runs, for 12 minutes"
              label="The line of this command in the Agent Caffeine menu, with Stop"
              title="npm"
            />
          </Card>
          <Card
            text="One click in Settings adds a skill to your agents. Then an agent keeps your Mac awake by itself before a long command. There is an MCP server too"
            title="Your agents can ask for it"
          >
            <PanelSurface
              className="flex flex-1 flex-col items-start justify-center gap-2.5 rounded-md bg-[color-mix(in_srgb,var(--panel-fg)_4%,var(--panel))] px-4"
              label="Settings: the button Set up for agents, and the agents that get the skill"
            >
              <span className="flex h-[22px] items-center rounded-md bg-[var(--app-blue)] px-2.5 text-white">Set up for agents</span>
              <span className={`text-pretty text-[12px] ${MUTED}`}>
                Adds a skill to Claude Code, Codex and opencode, and links the command agent-caffeine.
              </span>
              <ul className="grid grid-cols-5 gap-1.5">
                {SKILL_AGENTS.map((agent) => (
                  <li
                    key={agent.name}
                    className="flex size-7 items-center justify-center rounded-lg bg-[color-mix(in_srgb,var(--panel-fg)_8%,transparent)]"
                  >
                    <AgentIcon className="size-[18px]" label={agent.name} name={agent.icon} />
                  </li>
                ))}
              </ul>
            </PanelSurface>
          </Card>
          <Card
            text="Ask for up to 12 hours, and release it when the work is done. Each hold has a line in the menu. A low battery, heat and a pause still let your Mac sleep"
            title="Hold for a time"
          >
            <Terminal
              command="agent-caffeine hold --for 2h"
              label="A terminal that runs agent-caffeine hold --for 2h"
              output="Agent Caffeine keeps your Mac awake until 14:30. Hold 4e5f6a7b."
            />
            <HoldRow
              detail="Keeps your Mac awake until 14:30"
              label="The line of this hold in the Agent Caffeine menu, with Stop"
              title="Command line"
            />
          </Card>
        </ul>
        {/* Until 1.0.1 is the download: remove this line then. */}
        <p className="text-center text-sm text-muted">From version 1.0.1</p>
      </div>
    </section>
  );
}
