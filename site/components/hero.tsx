import { AgentIcon } from "@/components/agent-icons";
import { BuyButton } from "@/components/buy-button";
import { DownloadButton, TryFree } from "@/components/download-button";
import { GridTexture } from "@/components/grid-texture";
import { HeroScene } from "@/components/hero-scene";
import { LaptopScene } from "@/components/laptop-scene";
import { agents, markedAgents } from "@/lib/agents";
import { PRICE } from "@/lib/pricing";
import { getLatestRelease, type Release } from "@/lib/release";

const SHOWN = markedAgents.slice(0, 7);
const MORE = agents.length - SHOWN.length;

/** The small glyphs of the line under the download, in the stroke of the page. Each box is the ink of its glyph, at the height of the capitals. */
const GLYPH = {
  "aria-hidden": true,
  className: "w-auto shrink-0 -translate-y-[0.08em]",
  fill: "none",
  stroke: "currentColor",
  strokeLinecap: "round",
  strokeLinejoin: "round",
  strokeWidth: 1.5,
} as const;

/** "a", "b" and "c" are the app over the closed laptop, in the cuts of `HeroScene`. "z" is the hero before them, kept for the comparison at `/hero-lab`. */
export type HeroVariant = "a" | "b" | "c" | "z";

function WorksWith() {
  return (
    <div className="flex flex-wrap items-center justify-center gap-x-3 gap-y-2 text-sm text-muted md:justify-start">
      <span>Works with</span>
      <ul className="flex items-center gap-3">
        {SHOWN.map((agent) => (
          <li key={agent.name} className="group relative flex text-fg">
            <AgentIcon className="size-6" label={agent.name} name={agent.icon} />
            <span
              aria-hidden="true"
              className="pointer-events-none absolute bottom-full left-1/2 mb-2 -translate-x-1/2 scale-[0.98] whitespace-nowrap rounded-md border border-border bg-bg px-2 py-1 text-xs text-fg opacity-0 shadow-[0_4px_12px_var(--shadow)] transition duration-quick ease-out group-hover:scale-100 group-hover:opacity-100 group-hover:delay-[80ms] motion-reduce:transition-none"
            >
              {agent.name}
            </span>
          </li>
        ))}
      </ul>
      <span>and {MORE} more</span>
    </div>
  );
}

function Cta({ release }: { release: Release | null }) {
  return release === null ? (
    <div className="flex flex-col items-center gap-3 md:items-start">
      <BuyButton placement="hero">Buy for {PRICE}</BuyButton>
      <p className="text-sm text-muted">Pay once. No subscription · macOS 13 or later, Apple silicon and Intel</p>
    </div>
  ) : (
    <div className="flex flex-col items-center gap-4 md:items-start">
      <DownloadButton release={release} placement="hero">
        <TryFree />
      </DownloadButton>
      <ul className="flex flex-wrap items-center justify-center gap-x-3 gap-y-1.5 text-sm text-muted md:justify-start">
        <li className="flex items-center gap-1.5">
          <svg {...GLYPH} height="10.5" viewBox="0 0 12 10.5">
            <path d="M.75 3h10.5v2.5H.75zM1.75 5.5v4.25h8.5V5.5M6 3v6.75M6 3C4.6 3 3.4 2.6 3.4 1.7c0-.6.45-.95.95-.95C5.5.75 6 2 6 3Zm0 0c1.4 0 2.6-.4 2.6-1.3 0-.6-.45-.95-.95-.95C6.5.75 6 2 6 3Z" />
          </svg>
          Free for 7 days
        </li>
        <li aria-hidden="true" className="-translate-y-[0.09em]">
          ·
        </li>
        <li>Then {PRICE} once</li>
        <li aria-hidden="true" className="hidden -translate-y-[0.09em] sm:block">
          ·
        </li>
        <li className="flex basis-full items-center justify-center gap-1.5 sm:basis-auto">
          <svg {...GLYPH} height="10" viewBox="0 0 13.5 10">
            <rect height="8.5" rx="1.5" width="12" x=".75" y=".75" />
            <path d="M.75 3.6h12M3.25 6.6h2" />
          </svg>
          No account, no card
        </li>
      </ul>
    </div>
  );
}

/** The hero before the app came into it: a laptop that runs Claude Code and closes. */
function ClassicHero({ release }: { release: Release | null }) {
  return (
    <section className="relative isolate mx-auto grid w-full max-w-[1120px] items-center gap-6 pb-12 pt-8 text-center md:grid-cols-[minmax(0,7fr)_minmax(0,5fr)] md:min-h-[calc(100svh-3.5rem)] md:gap-12 md:py-20 md:text-left">
      <GridTexture />
      <div className="relative z-10 flex flex-col items-center gap-7 md:items-start">
        <div className="flex flex-col items-center gap-5 md:items-start">
          <h1 className="max-w-[16ch] text-balance text-[clamp(2.25rem,9vw,2.75rem)] font-medium leading-[1.1] tracking-[-0.02em] md:max-w-none md:text-[clamp(2.5rem,4.2vw,3.25rem)]">
            Your agents keep working <span className="text-accent">with the lid closed</span>
          </h1>
          <p className="max-w-[26rem] text-pretty text-lg leading-relaxed text-muted md:max-w-[30rem]">
            A menu bar app for Mac. It keeps your Mac awake while Claude Code, Codex or another AI coding agent works, and lets it sleep when the work is done
          </p>
        </div>
        <WorksWith />
        <Cta release={release} />
      </div>
      {/* The base fills 68.28% of the scene, so the scene runs 23.23% of its column past each side and the base spans the column exactly. */}
      <div className="md:-mx-[23.23%]">
        <LaptopScene />
      </div>
    </section>
  );
}

export async function Hero({ variant = "a" }: { variant?: HeroVariant }) {
  const release = await getLatestRelease();
  if (variant === "z") {
    return <ClassicHero release={release} />;
  }
  // On a phone the picture comes right after the headline, so the first screen shows it with the closed laptop. Side by side, the words and the download are one column.
  return (
    <section className="relative isolate mx-auto grid w-full max-w-[1120px] items-center gap-x-12 gap-y-7 pb-12 pt-8 text-center md:grid-cols-[minmax(0,7fr)_minmax(0,5fr)] md:grid-rows-[1fr_auto_auto_auto_1fr] md:min-h-[calc(100svh-3.5rem)] md:py-10 md:text-left">
      <GridTexture />
      <h1 className="relative z-10 text-balance text-[clamp(2.25rem,9vw,2.75rem)] font-medium leading-[1.1] tracking-[-0.02em] md:col-start-1 md:row-start-2 md:text-[clamp(2.5rem,4.2vw,3.25rem)]">
        Close your Mac. <span className="text-accent md:block">Your agents keep working</span>
      </h1>
      <div className="md:col-start-2 md:row-span-5 md:row-start-1">
        <HeroScene cut={variant} />
      </div>
      <p className="relative z-10 mx-auto max-w-[26rem] text-pretty text-lg leading-relaxed text-muted md:col-start-1 md:row-start-3 md:mx-0 md:-mt-2 md:max-w-[31rem]">
        agent caffeine keeps your Mac awake while Claude Code, Codex or Cursor works, also with the lid closed. It lets your Mac sleep when they are done
      </p>
      <div className="relative z-10 flex flex-col items-center gap-7 md:col-start-1 md:row-start-4 md:items-start">
        <WorksWith />
        <Cta release={release} />
      </div>
    </section>
  );
}
