import { isValidElement } from "react";
import type { ReactNode } from "react";
import { PRICE_LIST } from "@/lib/pricing";

type FaqItem = { question: string; answer: ReactNode };

/** The question a page with a download leads with. */
const trialItem: FaqItem = {
  question: "Is there a free trial?",
  answer: (
    <>
      Yes. agent caffeine is a free download, and every feature works for 7 days from the first
      time you open it, with no account, no card and no key. After 7 days it stops keeping your
      Mac awake until you enter a license key, and your settings stay. A key costs {PRICE_LIST},
      paid once.
    </>
  ),
};

const questions: FaqItem[] = [
  {
    question: "How does it know that an agent is working?",
    answer: (
      <>
        Claude Code and Codex say what they do: working, waiting for you, or idle. agent caffeine
        reads that on your Mac. It also watches the commands an agent started, so a build that is
        still busy keeps your Mac awake after the agent is done. For other agents it watches signs
        of work, such as a running command or a write to the session file. For Claude Code, Codex,
        Droid and opencode you can switch on better detection in Preferences. The agent then tells
        agent caffeine its state directly, and you can switch it off again at any time.
      </>
    ),
  },
  {
    question: "What happens when an agent waits for my answer?",
    answer: (
      <>
        Your Mac stays awake for 5 minutes, so you can answer. After that it can sleep. An idle
        agent does not keep your Mac awake in the default mode. You can change the times in
        Preferences.
      </>
    ),
  },
  {
    question: "Does it work with the lid closed on battery?",
    answer: (
      <>
        Yes. With the lid closed on power it works from the start. On battery it needs a small
        helper that you allow once in System Settings. When the battery is at 20%, or your
        Mac gets too hot, agent caffeine lets your Mac sleep and tells you why in a notification.
        You can change this level or turn it off in Preferences.
      </>
    ),
  },
  {
    question: "Can I reach my agent from my phone while the lid is closed?",
    answer: (
      <>
        Yes, while your Mac is awake. Choose Stay reachable in the menu, and your Mac stays awake
        for 1, 2 or 4 hours, also when no agent works. A message from your phone, with Claude Code
        Remote Control or Codex remote, then reaches your agent. On battery with the lid closed
        this needs the helper, and it uses about 1% of battery per hour. A message cannot
        wake a Mac that sleeps.
      </>
    ),
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
];

/** The home page questions, rendered by the FAQ and read as plain text for structured data. */
export function faqItems(trial: boolean): FaqItem[] {
  return trial ? [trialItem, ...questions] : questions;
}

/** The plain text of an answer, so the structured data says exactly what the page shows. */
export function answerText(node: ReactNode): string {
  if (typeof node === "string" || typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map(answerText).join("");
  if (isValidElement<{ children?: ReactNode }>(node)) return answerText(node.props.children);
  return "";
}
