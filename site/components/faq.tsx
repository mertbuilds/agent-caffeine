"use client";

import { useId, useState } from "react";
import type { ReactNode } from "react";
import { faqItems } from "@/lib/faq";

function Question({ question, answer }: { question: string; answer: ReactNode }) {
  const id = useId();
  const [open, setOpen] = useState(true);
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
        {faqItems.map((item) => (
          <Question key={item.question} question={item.question} answer={item.answer} />
        ))}
      </div>
    </section>
  );
}
