import type { CSSProperties, ReactNode } from "react";

export const CLAUDE = "#D97757";
const GREEN = "#4eba65";
const TEXT = "#e5e5e5";
const DIM = "#8b8b8b";
const EDGE = "#5c5c5c";
const MODE = "#af87ff";

const PROMPT = "refactor the auth module";
const SPINNER = ["·", "✢", "✳", "✶", "✻", "✽", "✻", "✶", "✳", "✢"];

/** The spinner glyph Claude Code shows `seconds` into its work. */
export function spinnerAt(seconds: number): string {
  return SPINNER[Math.floor(seconds / 0.12) % SPINNER.length];
}

/** Elapsed time the way Claude Code writes it: `48s`, `2m 14s`. */
function elapsed(seconds: number): string {
  const whole = Math.floor(seconds);
  const minutes = Math.floor(whole / 60);
  return minutes > 0 ? `${minutes}m ${whole % 60}s` : `${whole}s`;
}

function tokens(seconds: number): string {
  const count = Math.round(seconds * 61);
  return count < 1000 ? `${count}` : `${(count / 1000).toFixed(1)}k`;
}

type Session = {
  /** How far the welcome box has faded in. */
  welcome: number;
  /** How much of the prompt is typed into the input box, from 0 to 1. */
  typed: number;
  /** How far the sent prompt has come into the transcript. */
  sent: number;
  /** How far each tool line has come in: Read, its result, Update, its result, Bash, its result. */
  steps: readonly number[];
  /** Seconds the agent has worked, or null once it is done or before it starts. */
  working: number | null;
  spinner: string;
  done: boolean;
  /** The transcript's opacity, for clearing the screen before a replay. */
  shown: number;
};

function Cell({ children, color }: { children: string; color?: string }) {
  return (
    <span className="inline-block w-[1ch] text-center" style={{ color }}>
      {children}
    </span>
  );
}

function Line({ children, shown = 1, style }: { children: ReactNode; shown?: number; style?: CSSProperties }) {
  if (shown <= 0) {
    return null;
  }
  return (
    <div
      className="overflow-hidden whitespace-pre"
      style={{ opacity: shown, transform: `translateY(${(1 - shown) * 0.35}em)`, ...style }}
    >
      {children}
    </div>
  );
}

function Tool({
  name,
  args,
  call,
  result,
  ok,
  children,
}: {
  name: string;
  args: string;
  call: number;
  result: number;
  ok: boolean;
  children: ReactNode;
}) {
  if (call <= 0) {
    return null;
  }
  return (
    <div>
      <Line shown={call}>
        <Cell color={ok ? GREEN : DIM}>⏺</Cell> <b>{name}</b>({args})
      </Line>
      <Line shown={result}>
        {"  "}
        <Cell color={DIM}>⎿</Cell>
        {"  "}
        {children}
      </Line>
    </div>
  );
}

export function Terminal({ session }: { session: Session }) {
  const { welcome, typed, sent, steps, working, spinner, done, shown } = session;
  const [read, readResult, update, updateResult, bash, bashResult] = steps;

  return (
    <div
      aria-hidden="true"
      className="h-full bg-[#0d0d0d] px-[1ch] text-left pb-[0.3em] pt-[1.1em] text-[calc(100cqw/42)] leading-[1.35] [font-variant-ligatures:none]"
      style={{ color: TEXT, fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace" }}
    >
      <div className="flex h-full flex-col justify-end overflow-hidden">
        <div className="flex min-h-full shrink-0 flex-col">
          <div className="flex flex-col gap-[1.35em]" style={{ opacity: shown }}>
            <div
              className="w-[29ch] rounded-[0.4em] border px-[1ch] py-[0.35em]"
              style={{ borderColor: CLAUDE, opacity: welcome }}
            >
              <div className="whitespace-pre">
                <Cell color={CLAUDE}>✻</Cell> Welcome to <b>Claude Code</b>!
              </div>
            </div>
            {sent > 0 ? (
              <Line shown={sent} style={{ backgroundColor: "#262626", marginInline: "-1ch", paddingInline: "1ch" }}>
                <span style={{ color: DIM }}>&gt;</span> {PROMPT}
              </Line>
            ) : null}
            <Tool name="Read" args="src/auth/session.ts" call={read} result={readResult} ok={readResult > 0}>
              Read <b>214</b> lines
            </Tool>
            <Tool name="Update" args="src/auth/session.ts" call={update} result={updateResult} ok={updateResult > 0}>
              Updated <b>src/auth/session.ts</b> with <b>18</b> additions
              and <b>31</b> removals
            </Tool>
            <Tool name="Bash" args="bun test" call={bash} result={bashResult} ok={done}>
              {done ? "142 pass, 0 fail" : <span style={{ color: DIM }}>Running…</span>}
            </Tool>
            {done ? (
              <Line>
                <Cell>⏺</Cell> Done. The auth module is refactored and all 142 tests pass.
              </Line>
            ) : null}
            {working === null ? null : (
              <Line>
                <span style={{ color: CLAUDE }}>
                  <Cell>{spinner}</Cell> Refactoring…
                </span>{" "}
                <span style={{ color: DIM }}>
                  ({elapsed(working)} · ↓ {tokens(working)} tokens · esc to interrupt)
                </span>
              </Line>
            )}
          </div>
          <div className="mt-[1.35em]">
            <div className="whitespace-pre rounded-[0.4em] border px-[1ch] py-[0.6em]" style={{ borderColor: EDGE }}>
              {"> "}
              {sent > 0 ? null : PROMPT.slice(0, Math.round(typed * PROMPT.length))}
              <span className="inline-block w-[1ch] align-[-0.2em]" style={{ backgroundColor: TEXT, height: "1.2em" }} />
            </div>
            <div className="whitespace-pre">
              {"  "}
              <span style={{ color: MODE }}>⏵⏵ accept edits on</span>
              <span style={{ color: DIM }}> (shift+tab to cycle)</span>
            </div>
          </div>
          <div className="grow" />
        </div>
      </div>
    </div>
  );
}
