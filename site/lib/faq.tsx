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
    question: "I bought agent caffeine before license keys existed. Do I need to pay again?",
    answer: (
      <>
        No. Your key is in your{" "}
        <a href="https://polar.sh/mertbuilds/portal">Polar purchases</a>, under agent caffeine.
      </>
    ),
  },
];

/** The plain text of an answer, so the structured data says exactly what the page shows. */
export function answerText(node: ReactNode): string {
  if (typeof node === "string" || typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map(answerText).join("");
  if (isValidElement<{ children?: ReactNode }>(node)) return answerText(node.props.children);
  return "";
}
