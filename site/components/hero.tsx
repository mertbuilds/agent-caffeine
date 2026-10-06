import { AgentIcon } from "@/components/agent-icons";
import { BuyButton } from "@/components/buy-button";
import { DownloadButton } from "@/components/download-button";
import { GridTexture } from "@/components/grid-texture";
import { LaptopScene } from "@/components/laptop-scene";
import { agents, markedAgents } from "@/lib/agents";
import { PRICE } from "@/lib/pricing";
import { getLatestRelease, releaseDetails } from "@/lib/release";

const SHOWN = markedAgents.slice(0, 7);
const MORE = agents.length - SHOWN.length;

export async function Hero() {
  const release = await getLatestRelease();
  return (
    <section className="relative isolate mx-auto grid w-full max-w-[1120px] items-center gap-10 py-12 text-center md:grid-cols-[minmax(0,7fr)_minmax(0,5fr)] md:min-h-[calc(100svh-3.5rem)] md:gap-12 md:py-20 md:text-left">
      <GridTexture />
      <div className="relative z-10 flex flex-col items-center gap-7 md:items-start">
        <div className="flex flex-col items-center gap-5 md:items-start">
          <h1 className="max-w-[16ch] text-balance text-[clamp(2.25rem,9vw,2.75rem)] font-medium leading-[1.1] tracking-[-0.02em] md:max-w-none md:text-[clamp(2.5rem,4.2vw,3.25rem)]">
            Your agents keep working <span className="text-accent">with the lid closed</span>
          </h1>
          <p className="max-w-[26rem] text-pretty text-lg leading-relaxed text-muted md:max-w-[30rem]">
            agent caffeine keeps your Mac awake while they work, and lets it sleep when they are done
          </p>
        </div>
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
        {release === null ? (
          <div className="flex flex-col items-center gap-3 md:items-start">
            <BuyButton placement="hero">Buy for {PRICE}</BuyButton>
            <p className="text-sm text-muted">Pay once. No subscription · macOS 13 or later, Apple silicon and Intel</p>
          </div>
        ) : (
          <div className="flex flex-col items-center gap-3 md:items-start">
            <div className="flex flex-wrap items-center justify-center gap-3">
              <DownloadButton release={release} placement="hero">
                Download free trial
              </DownloadButton>
              <BuyButton placement="hero" variant="outline">
                Buy for {PRICE}
              </BuyButton>
            </div>
            <div className="flex flex-col gap-1 text-sm text-muted">
              <p>7 day free trial. Then {PRICE} once, no subscription</p>
              <p>{releaseDetails(release)}</p>
            </div>
          </div>
        )}
      </div>
      {/* The base fills 68.28% of the scene, so the scene runs 23.23% of its column past each side and the base spans the column exactly. */}
      <div className="md:-mx-[23.23%]">
        <LaptopScene />
      </div>
    </section>
  );
}
