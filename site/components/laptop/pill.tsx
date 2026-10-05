import { CLAUDE } from "./terminal";

/** Minutes and seconds at a fixed width, so the digits tick in place. */
function clock(seconds: number) {
  const whole = Math.floor(seconds);
  const minutes = String(Math.floor(whole / 60)).padStart(2, "\u2007");
  return `${minutes}m ${String(whole % 60).padStart(2, "0")}s`;
}

function ClaudeCodeIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-[1.15em] w-[1.15em] shrink-0" aria-hidden="true">
      <path
        fill={CLAUDE}
        fillRule="evenodd"
        d="M20.998 10.949H24v3.102h-3v3.028h-1.487V20H18v-2.921h-1.487V20H15v-2.921H9V20H7.488v-2.921H6V20H4.487v-2.921H3V14.05H0V10.95h3V5h17.998v5.949zM6 10.949h1.488V8.102H6v2.847zm10.51 0H18V8.102h-1.49v2.847z"
      />
    </svg>
  );
}

function Cup() {
  return (
    <svg viewBox="0 0 24 24" className="h-[1.1em] w-[1.1em] shrink-0" aria-hidden="true">
      <path fill="var(--accent)" d="M4 8h13v6a6 6 0 0 1-6 6h-1a6 6 0 0 1-6-6V8z" />
      <path
        fill="none"
        stroke="var(--accent)"
        strokeWidth="2"
        d="M17 10h1.5a2.5 2.5 0 0 1 0 5H16.5"
      />
    </svg>
  );
}

type PillProps = {
  /** How far the pill has come in, from 0 to 1. */
  shown: number;
  spinner: string;
  seconds: number;
};

/** The note above the closed laptop: Claude Code is still working. */
export function Pill({ shown, spinner, seconds }: PillProps) {
  if (shown <= 0) {
    return null;
  }
  return (
    <div
      className="absolute left-1/2 bottom-[47%] flex items-center gap-[0.6em] whitespace-nowrap rounded-full border border-[var(--border)] bg-[var(--bg)] px-[1em] py-[0.55em] text-[clamp(11px,2.3cqw,16px)] leading-none text-fg"
      style={{
        opacity: shown,
        transform: `translate(-50%, ${(1 - shown) * 0.6}em) scale(${0.96 + shown * 0.04})`,
        boxShadow: "0 0.5em 1.5em var(--shadow)",
      }}
    >
      <ClaudeCodeIcon />
      <span className="inline-block w-[1ch] text-center font-mono" style={{ color: CLAUDE }}>
        {spinner}
      </span>
      <span>Still working</span>
      <span className="tabular-nums text-muted">{clock(seconds)}</span>
      <Cup />
    </div>
  );
}
