import type { ReactNode } from "react";
import { AgentIcon, type AgentIconName } from "@/components/agent-icons";
import { AgentMark, PanelSurface } from "@/components/agents-panel";
import { SectionHeading } from "@/components/section-heading";

/** Still cuts of an agent, of what it runs and of the app, with the words of `PanelText.swift` (the line of a hold) and of the command line tool. */
const MUTED = "text-[var(--panel-muted)]";
const BOX = "rounded-md border border-[var(--panel-line)] bg-bg px-2.5 py-2";
const CODE = "font-mono text-[0.9em]";

type Example = {
  agent: { name: string; icon: AgentIconName; prompt: string };
  ask: string;
  /** A command the agent puts the tool in front of, or a call of the MCP tool `hold_awake`. */
  run: { command: string } | { tool: string; input: string };
  /** The line of the hold in the menu: the reason, and what `PanelText.hold` says below it. */
  row: { title: string; detail: string };
};

const EXAMPLES: readonly Example[] = [
  {
    agent: { name: "Claude Code", icon: "claudecode", prompt: ">" },
    ask: "Render the final animation and tell me when it is done",
    run: { command: 'agent-caffeine hold --reason "Blender render" -- blender -b scene.blend -a' },
    row: { title: "Blender render", detail: "Keeps your Mac awake while it runs, for 42 minutes" },
  },
  {
    agent: { name: "Codex", icon: "codex", prompt: "›" },
    ask: "Train the model overnight",
    run: { command: 'agent-caffeine hold --reason "Model training" -- python train.py' },
    row: { title: "Model training", detail: "Keeps your Mac awake while it runs, for 3 hours" },
  },
  {
    agent: { name: "Cursor", icon: "cursor", prompt: "→" },
    ask: "Run the full test suite, I will close the lid",
    run: { command: 'agent-caffeine hold --reason "Test suite" -- npm test' },
    row: { title: "Test suite", detail: "Keeps your Mac awake while it runs, for 18 minutes" },
  },
  {
    agent: { name: "opencode", icon: "opencode", prompt: ">" },
    ask: "Migrate the database, it takes about an hour",
    run: { tool: "hold_awake", input: 'minutes: 90, reason: "Database migration"' },
    row: { title: "Database migration", detail: "Keeps your Mac awake until 14:30" },
  },
];

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

/** One part of an example: what it is, and the cut of it. */
function Step({ children, label }: { children: ReactNode; label: string }) {
  return (
    <div className="flex min-w-0 flex-col gap-1">
      <p className="px-1 text-[12px] leading-4 text-muted">{label}</p>
      {children}
    </div>
  );
}

/** A line of a terminal. A line that wraps goes on under its text, not under its `mark`. */
function Line({ children, mark }: { children: ReactNode; mark?: string }) {
  return (
    <p className="flex min-w-0 gap-[1ch] font-mono text-[12px] leading-[18px]">
      {mark === undefined ? null : (
        <span aria-hidden="true" className="shrink-0 text-muted">
          {mark}
        </span>
      )}
      <span className="min-w-0 break-words">{children}</span>
    </p>
  );
}

/**
 * Radius: the card 20px, less its 8px padding is the cut at 12px, less its 6px padding is each box inside at 6px.
 * The three parts lie on the rows of the list, so each part is as tall as the same part of the card next to it.
 */
function ExampleCard({ example }: { example: Example }) {
  const { agent, ask, row, run } = example;
  return (
    <li className="row-span-3 grid grid-rows-subgrid rounded-[20px] border border-border p-2">
      <div className="row-span-3 grid min-w-0 grid-rows-subgrid gap-y-2.5 rounded-xl bg-surface p-1.5 pt-2">
        <Step label={`You ask ${agent.name}`}>
          <div className={`flex flex-1 items-start gap-2 ${BOX}`}>
            <AgentIcon className="mt-px size-4 shrink-0" name={agent.icon} />
            <Line mark={agent.prompt}>{ask}</Line>
          </div>
        </Step>
        <Step label={"command" in run ? `${agent.name} runs` : `${agent.name} calls the MCP tool`}>
          <div className={`flex flex-1 ${BOX}`}>
            {"command" in run ? (
              <Line mark="$">{run.command}</Line>
            ) : (
              <Line>
                {run.tool} <span className="text-muted">{run.input}</span>
              </Line>
            )}
          </div>
        </Step>
        <Step label="The Agent Caffeine menu shows">
          <PanelSurface
            className="panel-still flex flex-1 items-center gap-2 rounded-md py-1.5 pl-[7px] pr-3"
            label={`The line of ${row.title} in the Agent Caffeine menu, with Stop`}
          >
            <AgentMark icon={null} state="working" />
            <span className="flex min-w-0 flex-1 flex-col gap-px leading-4">
              <span className="truncate">{row.title}</span>
              <span className={`text-pretty text-[12px] tabular-nums ${MUTED}`}>{row.detail}</span>
            </span>
            <span aria-hidden="true" className="shrink-0 text-accent">
              Stop
            </span>
          </PanelSurface>
        </Step>
      </div>
    </li>
  );
}

function Fact({ children, title }: { children: ReactNode; title: string }) {
  return (
    <li className="flex flex-col gap-1.5">
      <h3 className="text-balance font-medium leading-snug">{title}</h3>
      {children}
    </li>
  );
}

const FACT_TEXT = "text-pretty text-sm leading-relaxed text-muted";

export function Examples() {
  return (
    <section id="examples" className="mx-auto flex w-full max-w-[1120px] scroll-mt-20 flex-col gap-10">
      <SectionHeading
        lead="The skill, the command line tool and the MCP server let any agent or script keep your Mac awake for a long job, then let it sleep"
        title="Ask your agent to run any long job"
      />
      <ul className="mx-auto grid w-full max-w-[36rem] gap-x-4 gap-y-4 lg:max-w-none lg:grid-cols-2">
        {EXAMPLES.map((example) => (
          <ExampleCard key={example.row.title} example={example} />
        ))}
      </ul>
      <ul className="mx-auto grid w-full max-w-[36rem] gap-x-8 gap-y-6 px-2 lg:max-w-none lg:grid-cols-3">
        <Fact title="A skill for your agents">
          <p className={FACT_TEXT}>One click in Settings adds it to Claude Code, Codex, opencode and others</p>
          <ul className="flex flex-wrap gap-2 pt-1">
            {SKILL_AGENTS.map((agent) => (
              <li key={agent.name} className="flex">
                <AgentIcon className="size-4" label={agent.name} name={agent.icon} />
              </li>
            ))}
          </ul>
        </Fact>
        <Fact title="A command for any script">
          <p className={FACT_TEXT}>
            <code className={CODE}>agent-caffeine hold -- &lt;command&gt;</code> keeps your Mac awake while the command runs. The exit code stays the same
          </p>
        </Fact>
        <Fact title="An MCP server">
          <p className={FACT_TEXT}>
            <code className={CODE}>agent-caffeine mcp</code> has three tools: <code className={CODE}>hold_awake</code>,{" "}
            <code className={CODE}>release</code> and <code className={CODE}>status</code>
          </p>
        </Fact>
      </ul>
      <p className="text-pretty text-center text-sm text-muted">A low battery, heat and a pause still let your Mac sleep</p>
    </section>
  );
}
