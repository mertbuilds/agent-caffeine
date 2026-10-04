import { BuyButton } from "@/components/buy-button";
import { HeroDrawing } from "@/components/drawings/hero-drawing";
import { GridTexture } from "@/components/grid-texture";

const PROMISES = [
  "Sees Claude Code, Codex and 40 more agents",
  "Works with the lid closed, on power or on battery",
  "Lets the Mac sleep when the work is done",
];

function Check() {
  return (
    <svg
      viewBox="0 0 24 24"
      width="16"
      height="16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      className="mt-1 shrink-0 text-muted"
    >
      <path d="M4.5 12.5l5 5L19.5 7" />
    </svg>
  );
}

export function Hero() {
  return (
    <section className="relative isolate mx-auto grid w-full max-w-[960px] items-center gap-12 py-12 md:grid-cols-2 md:py-24">
      <GridTexture />
      <div className="flex flex-col gap-6">
        <h1 className="text-balance text-[clamp(2rem,8vw,2.5rem)] font-medium leading-[1.15] tracking-[-0.02em] md:text-[clamp(2.5rem,4.5vw,3rem)]">
          Keep your Mac awake while your agents work,{" "}
          <span className="text-accent">even with the lid closed</span>
        </h1>
        <ul className="flex flex-col gap-2">
          {PROMISES.map((promise) => (
            <li key={promise} className="flex items-start gap-2 text-balance">
              <Check />
              <span>{promise}</span>
            </li>
          ))}
        </ul>
        <div className="flex flex-col gap-3">
          <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
            <BuyButton placement="hero">Buy Agent Caffeine · $9</BuyButton>
            <p className="text-sm text-muted">Pay once. No subscription</p>
          </div>
          <p className="text-sm text-muted">macOS 13 or later. Signed and notarized</p>
        </div>
      </div>
      <HeroDrawing />
    </section>
  );
}
