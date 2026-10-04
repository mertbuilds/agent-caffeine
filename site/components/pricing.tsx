import { BuyButton } from "@/components/buy-button";

export function Pricing() {
  return (
    <section className="mx-auto w-full max-w-[960px]">
      <div className="mx-auto flex max-w-[640px] flex-col items-center gap-6 rounded-lg border border-border bg-surface px-6 py-12 text-center md:py-16">
        <div className="flex flex-col gap-3">
          <p className="text-7xl font-medium tabular-nums leading-none tracking-[-0.02em]">$9</p>
          <p className="text-muted">Once. Lifetime updates. No subscription</p>
        </div>
        <BuyButton placement="pricing">Buy Agent Caffeine</BuyButton>
        <p className="text-sm text-muted">Signed, notarized and Gatekeeper clean</p>
      </div>
    </section>
  );
}
