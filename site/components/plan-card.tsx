"use client";

import NumberFlow from "@number-flow/react";
import { useState, type KeyboardEvent, type ReactNode } from "react";
import { BuyButton } from "@/components/buy-button";
import { BASE_PLAN, PLANS, dollars, macs, type Plan } from "@/lib/pricing";

const PRICE_FORMAT = { style: "currency", currency: "USD", maximumFractionDigits: 0 } as const;

/**
 * The words of the pricing card: the price of the picked plan, the plans to pick from, and the button that buys the picked one.
 * With a download, the free trial leads: its line stands over the price, and its button before the buy.
 */
export function PlanCard({ download = null }: { download?: ReactNode }) {
  const [picked, setPicked] = useState<Plan["id"]>(BASE_PLAN.id);
  const at = Math.max(0, PLANS.findIndex((entry) => entry.id === picked));
  const plan = PLANS[at];

  function onKey(event: KeyboardEvent<HTMLDivElement>) {
    const step = event.key === "ArrowRight" || event.key === "ArrowDown" ? 1 : event.key === "ArrowLeft" || event.key === "ArrowUp" ? -1 : 0;
    if (step === 0) {
      return;
    }
    event.preventDefault();
    const next = PLANS[(at + step + PLANS.length) % PLANS.length];
    setPicked(next.id);
    event.currentTarget.querySelector<HTMLElement>(`[data-plan="${next.id}"]`)?.focus();
  }

  return (
    <div className="flex flex-col items-center gap-8 md:items-start">
      <div className="flex flex-col items-center gap-5 md:items-start">
        <div className="flex flex-col items-center gap-3 md:items-start">
          {download === null ? null : <p className="text-lg">Free for 7 days, then</p>}
          <p className="text-7xl font-medium tabular-nums leading-none tracking-[-0.02em] md:text-8xl">
            <NumberFlow format={PRICE_FORMAT} locales="en-US" value={plan.price} />
          </p>
        </div>
        {PLANS.length > 1 && (
          <div className="flex flex-col items-center gap-2.5 md:items-start">
            <div
              aria-label="Plan"
              className="relative grid rounded-full bg-[rgba(8,30,90,0.28)] p-1 shadow-[inset_0_0_0_1px_rgba(255,255,255,0.18)]"
              onKeyDown={onKey}
              role="radiogroup"
              style={{ gridTemplateColumns: `repeat(${PLANS.length}, minmax(0, 1fr))` }}
            >
              <span
                aria-hidden="true"
                className="pointer-events-none absolute inset-y-1 left-1 rounded-full bg-white shadow-[0_1px_2px_rgba(8,30,90,0.25)] transition-transform duration-fast ease-smooth-out motion-reduce:transition-none"
                style={{ width: `calc((100% - 0.5rem) / ${PLANS.length})`, transform: `translateX(${at * 100}%)` }}
              />
              {PLANS.map((entry) => (
                <button
                  key={entry.id}
                  aria-checked={entry.id === plan.id}
                  className={`relative flex items-baseline justify-center gap-2 whitespace-nowrap rounded-full px-4 py-2 text-sm transition-colors duration-fast ease-smooth-out focus-visible:outline-white motion-reduce:transition-none sm:px-5 ${entry.id === plan.id ? "text-brand-deep" : "text-white"}`}
                  data-plan={entry.id}
                  onClick={() => setPicked(entry.id)}
                  role="radio"
                  tabIndex={entry.id === plan.id ? 0 : -1}
                  type="button"
                >
                  <span>{macs(entry)}</span>
                  <span className={`tabular-nums ${entry.id === plan.id ? "" : "opacity-75"}`}>{dollars(entry)}</span>
                </button>
              ))}
            </div>
          </div>
        )}
      </div>
      <div className="flex flex-col items-center gap-4 md:items-start">
        <div className="flex flex-wrap items-center justify-center gap-3 md:justify-start">
          {download}
          <BuyButton placement="pricing" plan={plan} variant={download === null ? "brand" : "brandOutline"}>
            Buy agent caffeine for <span className="tabular-nums">{dollars(plan)}</span>
          </BuyButton>
        </div>
        {/* A line may end only where a sentence ends. */}
        <p>Pay&nbsp;once. Lifetime&nbsp;updates. No&nbsp;subscription</p>
      </div>
    </div>
  );
}
