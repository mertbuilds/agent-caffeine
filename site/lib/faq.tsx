import { isValidElement } from "react";
import type { ReactNode } from "react";

/** The home page questions, rendered by the FAQ and read as plain text for structured data. */
export const faqItems: { question: string; answer: ReactNode }[] = [
  {
    question: "Does it work with the lid closed on battery?",
    answer: (
      <>
        Yes. With the lid closed on power it works from the start. On battery it works after you
        allow one admin prompt. That installs a small sudoers entry, and agent caffeine then turns
        on <code>pmset disablesleep</code> only while it keeps the Mac awake.
      </>
    ),
  },
  {
    question: "How does it keep the Mac awake?",
    answer: (
      <>
        It holds a <code>PreventUserIdleSystemSleep</code> assertion, the same one{" "}
        <code>caffeinate -i</code> uses, and <code>PreventSystemSleep</code> for a closed lid on
        power. The display can still sleep. The work keeps going.
      </>
    ),
  },
  {
    question: "How does it find my agents?",
    answer: (
      <>
        It reads the process list every 5 seconds and compares it with a list of agent names that
        you can edit. An agent counts as working while it, or a command it started, uses the CPU,
        and as idle while it waits at its prompt. About 2 minutes after its last work, an idle agent
        stops holding the Mac awake. For Claude Code it also reads the session files in{" "}
        <code>~/.claude/projects</code> to show each session and see if it is working.
      </>
    ),
  },
  {
    question: "Can it keep the Mac awake all the time?",
    answer: (
      <>
        Yes. Pick a mode in the menu or in Preferences. “While an agent is working”, the default,
        keeps the Mac awake only while an agent does work and lets it sleep when every agent is
        idle. “While an agent is open” keeps it awake as long as an agent runs, also when it waits at
        its prompt. “Always” keeps it awake until you switch agent caffeine off.
      </>
    ),
  },
  {
    question: "What about privacy?",
    answer: (
      <>
        No telemetry and no analytics. agent caffeine reads the process list and the Claude Code
        session files in <code>~/.claude/projects</code>{" "}
        on your own Mac. It makes two kinds of network calls: it checks caffeinagent.com for
        updates, and it checks your license key with Polar, sending the key and your Mac&apos;s
        model. Nothing about you or your agents leaves the Mac.
      </>
    ),
  },
  {
    question: "Is there a free trial?",
    answer:
      "Yes. You get 7 days with every feature and no card. After that agent caffeine stops keeping the Mac awake until you enter a license key.",
  },
  {
    question: "Can I use one key on two Macs?",
    answer:
      "One key works on one Mac at a time. To move it, deactivate this Mac in Preferences or in your Polar purchases, then activate the key on the other Mac.",
  },
  {
    question: "How do updates work?",
    answer:
      "The app checks for updates itself and installs them when you agree. You can also choose “Check for updates…” in the menu.",
  },
  {
    question: "I bought agent caffeine before license keys existed. Do I need to pay again?",
    answer: (
      <>
        No. Your key is in your{" "}
        <a href="https://polar.sh/mertbuilds/portal">Polar purchases</a>, under agent caffeine.
      </>
    ),
  },
  {
    question: "Which macOS versions?",
    answer: "macOS 13 Ventura or later. A universal binary for Apple silicon and Intel.",
  },
  {
    question: "Do I need a helper or special permissions?",
    answer:
      "Only for the battery option. Without it there are no daemons and no helpers, only a menu bar app.",
  },
  {
    question: "What if my agent is not on the list?",
    answer: "Open Preferences and type the process name. The list is yours to change.",
  },
];

/** The plain text of an answer, so the structured data says exactly what the page shows. */
export function answerText(node: ReactNode): string {
  if (typeof node === "string" || typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map(answerText).join("");
  if (isValidElement<{ children?: ReactNode }>(node)) return answerText(node.props.children);
  return "";
}
