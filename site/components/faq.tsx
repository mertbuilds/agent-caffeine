"use client";

import { useId, useState } from "react";
import type { ReactNode } from "react";

const ITEMS: { question: string; answer: ReactNode }[] = [
  {
    question: "Does it work with the lid closed on battery?",
    answer: (
      <>
        Yes. With the lid closed on power it works from the start. On battery it works after you
        allow one admin prompt. That installs a small sudoers entry, and Agent Caffeine then turns
        on <code>pmset disablesleep</code> only while an agent runs.
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
        you can edit. For Claude Code it also reads the session files in{" "}
        <code>~/.claude/projects</code> to show each session.
      </>
    ),
  },
  {
    question: "What about privacy?",
    answer: (
      <>
        No network calls and no telemetry. It reads files in <code>~/.claude/projects</code> and
        process names on your own Mac. Nothing leaves it.
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

function Question({ question, answer }: { question: string; answer: ReactNode }) {
  const id = useId();
  const [open, setOpen] = useState(false);
  const questionId = `${id}-question`;
  const answerId = `${id}-answer`;

  return (
    <div className="border-t border-border first:border-t-0">
      <h3>
        <button
          type="button"
          id={questionId}
          aria-expanded={open}
          aria-controls={answerId}
          onClick={() => setOpen(!open)}
          className="group flex w-full items-center justify-between gap-4 rounded py-4 text-left leading-normal"
        >
          <span className="text-pretty">{question}</span>
          <svg
            viewBox="0 0 24 24"
            width="16"
            height="16"
            fill="none"
            stroke="currentColor"
            strokeWidth="2.25"
            strokeLinecap="round"
            strokeLinejoin="round"
            aria-hidden="true"
            className={`shrink-0 transition-transform duration-fast ease-smooth-out motion-reduce:transition-none ${
              open ? "rotate-180 text-fg" : "text-muted group-hover:text-fg"
            }`}
          >
            <path d="M6 9l6 6 6-6" />
          </svg>
        </button>
      </h3>
      <div
        id={answerId}
        role="region"
        aria-labelledby={questionId}
        inert={!open}
        className={`grid transition-[grid-template-rows,opacity] duration-fast ease-smooth-out motion-reduce:transition-none ${
          open ? "grid-rows-[1fr] opacity-100" : "grid-rows-[0fr] opacity-0"
        }`}
      >
        <div className="min-h-0 overflow-hidden">
          <p className="pb-4 text-pretty leading-relaxed text-muted">{answer}</p>
        </div>
      </div>
    </div>
  );
}

export function Faq() {
  return (
    <section className="mx-auto flex w-full max-w-[640px] flex-col gap-6">
      <h2 className="text-balance text-[1.75rem] font-medium leading-[1.2] tracking-[-0.01em]">
        Questions
      </h2>
      <div>
        {ITEMS.map((item) => (
          <Question key={item.question} question={item.question} answer={item.answer} />
        ))}
      </div>
    </section>
  );
}
