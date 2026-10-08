import { isValidElement } from "react";
import type { ReactNode } from "react";
import { PRICE_LIST } from "@/lib/pricing";
import { BATTERY_FLOOR, BATTERY_RECOVERY } from "@/lib/simulator";

/** `open` is for an answer the page shows from the start. */
type FaqItem = { question: string; answer: ReactNode; open?: boolean };

/** What a reader asks before a download, first and open: what is new here, and what it costs in safety, battery and rights. */
const objections: FaqItem[] = [
  {
    question: "Does caffeinate or Amphetamine not do this already?",
    open: true,
    answer: (
      <>
        Not for agents. caffeinate and Amphetamine keep your Mac awake for a set time, or until a
        program quits or you stop them. They do not know if an agent works or is idle, so your Mac
        stays awake after the work is done, or sleeps in the middle of it. A command such as
        caffeinate also cannot keep your Mac awake when you close the lid on battery: macOS sleeps
        then. Agent Caffeine has a small helper for that, which you allow once. It reads what your
        agents do, keeps your Mac awake while they work, and lets it sleep when they are done.
      </>
    ),
  },
  {
    question: "Is it safe in a bag?",
    open: true,
    answer: (
      <>
        Not in a closed bag. Do not put your Mac in a closed bag while an agent works: a Mac that
        works gets warm, and a closed bag keeps the heat in. Agent Caffeine has two stops for
        safety. When your Mac gets too hot, it always lets your Mac sleep. On battery it lets your
        Mac sleep at {BATTERY_FLOOR}% and starts again at {BATTERY_FLOOR + BATTERY_RECOVERY}%, or
        when you plug in. You can change this level or turn it off in Settings. A notification
        tells you why your Mac slept. The display is off while the lid is closed. Before you put
        your Mac in a closed bag, pause Agent Caffeine, and your Mac sleeps as usual.
      </>
    ),
  },
  {
    question: "Does it drain my battery when nothing runs?",
    open: true,
    answer: (
      <>
        No. When no agent works, Agent Caffeine lets your Mac sleep as usual. In the default mode
        it keeps your Mac awake while an agent works, for 2 minutes after it finishes, and for 5
        minutes when it waits for your answer. An agent that is open and idle does not keep your
        Mac awake. You can change the times in Settings.
      </>
    ),
  },
  {
    question: "Does it need admin rights?",
    open: true,
    answer: (
      <>
        Only for one case: the lid is closed and your Mac runs on battery. Only the system can
        stop macOS from sleeping then, so Agent Caffeine has a small helper that runs with system
        rights. You allow it once in System Settings &gt; General &gt; Login Items. It changes one
        sleep setting of macOS while Agent Caffeine keeps your Mac awake, and changes it back
        after. You can remove it in the app&apos;s Settings. Everything else works without the
        helper, also the lid closed on the power adapter.
      </>
    ),
  },
];

/** The question a page with a download adds, after the objections. */
const trialItem: FaqItem = {
  question: "Is there a free trial?",
  answer: (
    <>
      Yes. Agent Caffeine is a free download for macOS 13 or later, on Apple silicon and Intel.
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
        Cursor, Droid, opencode and Pi you can switch on better detection in Settings. The agent then
        tells Agent Caffeine its state directly, and you can switch it off again at any time.
      </>
    ),
  },
  {
    question: "What happens when an agent waits for my answer?",
    answer: (
      <>
        Your Mac stays awake for 5 minutes, so you can answer. After that it can sleep. An idle
        agent does not keep your Mac awake in the default mode. You can change the times in
        Settings.
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
        Yes. Deactivate it on the old Mac, in Settings or in your{" "}
        <a href="https://polar.sh/mertbuilds/portal" target="_blank" rel="noreferrer">
          Polar purchases
        </a>
        , then enter it on the new Mac.
      </>
    ),
  },
];

/** The home page questions, rendered by the FAQ and read as plain text for structured data. */
export function faqItems(trial: boolean): FaqItem[] {
  return trial ? [...objections, trialItem, ...questions] : [...objections, ...questions];
}

/** The plain text of an answer, so the structured data says exactly what the page shows. */
export function answerText(node: ReactNode): string {
  if (typeof node === "string" || typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map(answerText).join("");
  if (isValidElement<{ children?: ReactNode }>(node)) return answerText(node.props.children);
  return "";
}
