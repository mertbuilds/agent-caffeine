import { isValidElement } from "react";
import type { ReactNode } from "react";
import { PRICE_LIST } from "@/lib/pricing";
import { BATTERY_FLOOR, BATTERY_RECOVERY, REACHABLE_COST } from "@/lib/simulator";

type FaqItem = { question: string; answer: ReactNode };

/** The question a page with a download leads with. */
const trialItem: FaqItem = {
  question: "Is there a free trial?",
  answer: (
    <>
      Yes. agent caffeine is a free download for macOS 13 or later, on Apple silicon and Intel.
      Every feature works for 7 days from the first time you open it, with no account, no card
      and no key. After 7 days it stops keeping your Mac awake until you enter a license key, and
      your settings stay. A key costs {PRICE_LIST}, paid once.
    </>
  ),
};

const questions: FaqItem[] = [
  {
    question: "How does it know that an agent is working?",
    answer: (
      <>
        Claude Code, Codex and Cursor say what they do: working, waiting for you, or idle. agent
        caffeine reads that on your Mac. It also watches the commands an agent started, so a build that is
        still busy keeps your Mac awake after the agent is done. For other agents it watches signs
        of work, such as a running command or a write to the session file. For Claude Code, Codex,
        Cursor, Droid and opencode you can switch on better detection in Preferences. The agent then tells
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
    question: "What is the helper, and when do I need it?",
    answer: (
      <>
        You need it in one case: the lid is closed and your Mac runs on battery. With the lid
        closed on the power adapter, agent caffeine works from the start. The helper is a
        background item of agent caffeine. It changes one sleep setting of macOS while agent
        caffeine keeps your Mac awake, and changes it back after. You allow it once in System
        Settings, and you can remove it in Preferences.
      </>
    ),
  },
  {
    question: "Is it safe for my battery and my Mac?",
    answer: (
      <>
        Yes, with one rule: do not put a working Mac in a closed bag. On battery, agent caffeine
        lets your Mac sleep at {BATTERY_FLOOR}% and starts again at{" "}
        {BATTERY_FLOOR + BATTERY_RECOVERY}%, or when you plug in. You can change this level or
        turn it off in Preferences. When your Mac gets too hot, agent caffeine always lets it
        sleep. A notification tells you why. The display goes dark with the lid. With the lid
        closed and no agent at work, an awake Mac uses about {REACHABLE_COST}% of battery per
        hour.
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
        this needs the helper. A message cannot wake a Mac that sleeps.
      </>
    ),
  },
  {
    question: "Can I get a refund?",
    answer: (
      <>
        No. All sales are final, and there are no refunds after purchase, because the full app is
        free to try for 7 days first.
      </>
    ),
  },
  {
    question: "Can I move my key to a new Mac?",
    answer: (
      <>
        Yes. Deactivate it on the old Mac, in Preferences or in your{" "}
        <a href="https://polar.sh/mertbuilds/portal">Polar purchases</a>, then enter it on the new
        Mac.
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
