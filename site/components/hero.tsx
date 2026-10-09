import { AgentIcon } from "@/components/agent-icons";
import { BuyButton } from "@/components/buy-button";
import { DownloadButton, TryFree } from "@/components/download-button";
import { GridTexture } from "@/components/grid-texture";
import { HeroScene } from "@/components/hero-scene";
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

function WorksWith() {
  return (
    <div className="flex flex-wrap items-center justify-center gap-x-3 gap-y-2 text-sm text-muted lg:justify-start">
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
    <div className="flex flex-col items-center gap-3 lg:items-start">
      <BuyButton placement="hero">Buy for {PRICE}</BuyButton>
      <p className="text-sm text-muted">Pay once. No subscription · macOS 13 or later, Apple silicon and Intel</p>
    </div>
  ) : (
    <div className="flex flex-col items-center gap-4 lg:items-start">
      <DownloadButton release={release} placement="hero">
        <TryFree />
      </DownloadButton>
      <ul className="flex flex-wrap items-center justify-center gap-x-3 gap-y-1.5 text-sm text-muted lg:justify-start">
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

export async function Hero() {
  const release = await getLatestRelease();
  // On a phone the picture comes right after the headline, so the first screen shows it with the closed laptop. Side by side, the words and the download are one column.
  // Side by side the hero is the whole first screen, with its content in the middle, so the space under the content is already the gap to the next section. The margin takes most of the page's own gap away, and leaves the next heading just under the first screen.
  return (
    <section className="relative isolate mx-auto grid w-full max-w-[1120px] items-center gap-x-12 gap-y-5 pb-12 pt-8 text-center lg:grid-cols-[minmax(0,7fr)_minmax(0,5fr)] lg:grid-rows-[1fr_auto_auto_auto_1fr] lg:gap-y-7 lg:-mb-[5.5rem] lg:min-h-[calc(100svh-3.5rem)] lg:py-10 lg:text-left">
      <GridTexture />
      <h1 className="relative z-10 text-[clamp(2.25rem,9vw,2.75rem)] font-medium leading-[1.1] tracking-[-0.02em] lg:col-start-1 lg:row-start-2 lg:text-[clamp(2.5rem,4.2vw,3rem)]">
        Close your lid <span className="block text-balance text-accent xl:whitespace-nowrap">Come back to finished work</span>
      </h1>
      <div className="min-w-0 lg:col-start-2 lg:row-span-5 lg:row-start-1">
        <HeroScene />
      </div>
      <p className="relative z-10 mx-auto max-w-[26rem] text-pretty text-lg leading-relaxed text-muted lg:col-start-1 lg:row-start-3 lg:mx-0 lg:-mt-2 lg:max-w-[31rem]">
        Agent Caffeine keeps your Mac awake while your agents work, also with the lid closed. Then it lets your Mac sleep
      </p>
      <div className="relative z-10 flex flex-col items-center gap-7 lg:col-start-1 lg:row-start-4 lg:items-start">
        <WorksWith />
        <Cta release={release} />
      </div>
    </section>
  );
}
