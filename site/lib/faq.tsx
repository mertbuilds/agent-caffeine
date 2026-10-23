import { isValidElement } from "react";
import type { ReactNode } from "react";
import { agentsMoreThan } from "@/lib/agents";
import { BATTERY_FLOOR } from "@/lib/simulator";
import { FULL_PRICE, LAUNCH_PRICE_ACTIVE, MACS, PORTAL_URL, PRICE, dollars } from "@/lib/pricing";

/** `id` names the question where it is counted, and stays when the list is put in another order. `open` is for an answer the page shows from the start. */
type FaqItem = { id: string; question: string; answer: ReactNode; open?: boolean };

/** Short answers, the direct one first. The first three are what a reader asks before a download, and they are open from the start. */
const questions: FaqItem[] = [
  {
    id: "caffeinate",
    question: "Does caffeinate or Amphetamine not do this already?",
    open: true,
    answer: (
      <>
        They keep your Mac awake until a set time or until you stop them. They do not know when an
        agent works. Agent Caffeine does, also with the lid closed on battery, and lets your Mac
        sleep after.
      </>
    ),
  },
  {
    id: "battery",
    question: "Does it drain my battery when nothing runs?",
    open: true,
    answer: (
      <>
        No. When no agent works, your Mac sleeps as usual. On battery, Agent Caffeine also stops
        at {BATTERY_FLOOR}%.
      </>
    ),
  },
  {
    id: "admin",
    question: "Does it need admin rights?",
    open: true,
    answer: (
      <>
        Only to stay awake with the lid closed on battery. You allow a small helper once in System
        Settings. Everything else works without it.
      </>
    ),
  },
  {
    id: "detection",
    question: "How does it know that an agent is working?",
    answer: (
      <>
        Claude Code, Codex and Cursor report their state. opencode, Pi and Droid do too, after you
        turn it on for each in Settings. For other agents it watches signs of work. It knows{" "}
        <a href="#agents">more than {agentsMoreThan} agents</a>.
      </>
    ),
  },
  {
    id: "waiting",
    question: "What happens when an agent waits for my answer?",
    answer: <>Your Mac stays awake for 5 minutes, so you can answer. After that it can sleep.</>,
  },
  {
    id: "phone",
    question: "Can I reach my agent from my phone while the lid is closed?",
    answer: (
      <>
        Yes. Choose Stay reachable, and your Mac stays awake for 1, 2 or 4 hours. On battery with
        the lid closed it needs the helper. A message cannot wake a sleeping Mac.
      </>
    ),
  },
  {
    id: "script",
    question: "Can it keep my Mac awake for a script or a render?",
    answer: (
      <>
        Yes. Put agent-caffeine hold -- in front of the command. Your Mac stays awake while the
        command runs, and can sleep when it ends.
      </>
    ),
  },
  {
    id: "mcp",
    question: "Does it have an MCP server?",
    answer: (
      <>
        Yes. The command agent-caffeine mcp gives an agent three tools: hold_awake, release and
        status. A hold ends when the session of the agent ends.
      </>
    ),
  },
  {
    id: "privacy",
    question: "Does it send my data anywhere?",
    answer: (
      <>
        No. The app has no telemetry, no analytics and no account. It only checks for updates and
        checks your license key. The <a href="/privacy">privacy page</a> has the details.
      </>
    ),
  },
  {
    id: "price",
    question: "What does it cost?",
    answer: (
      <>
        {LAUNCH_PRICE_ACTIVE ? `${PRICE} once at the launch price. The full price is ${dollars(FULL_PRICE)}.` : `${PRICE} once.`} One
        key works on up to {MACS} Macs and includes 1 year of updates. Every feature is free to try
        for 7 days first, with no account and no card.
      </>
    ),
  },
  {
    id: "updates",
    question: "What happens after a year?",
    answer: (
      <>
        The app keeps working, with no end date. Your key gets every update for 1 year after you
        buy. A version that comes out after that needs a new key.
      </>
    ),
  },
  {
    id: "key",
    question: "I lost my key, or I have a new Mac. What now?",
    answer: (
      <>
        Your key is in <a href={PORTAL_URL}>your purchases on Polar</a>. To move it to another Mac,
        deactivate it on the old one, in the app or in your purchases, then enter it on the new one.
      </>
    ),
  },
  {
    id: "refund",
    question: "Can I get a refund?",
    answer: <>No. All sales are final, because the full app is free to try for 7 days first.</>,
  },
];

/** The home page questions, rendered by the FAQ and read as plain text for structured data. */
export function faqItems(): FaqItem[] {
  return questions;
}

/** The plain text of an answer, so the structured data says exactly what the page shows. */
export function answerText(node: ReactNode): string {
  if (typeof node === "string" || typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map(answerText).join("");
  if (isValidElement<{ children?: ReactNode }>(node)) return answerText(node.props.children);
  return "";
}
