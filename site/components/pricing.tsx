import Image from "next/image";
import { BuyButton } from "@/components/buy-button";
import { DownloadButton, TryFree } from "@/components/download-button";
import { FULL_PRICE, LAUNCH_PRICE_ACTIVE, MACS, PORTAL_URL, PRICE, dollars } from "@/lib/pricing";
import { getLatestRelease } from "@/lib/release";

const GRID_LINE = "rgba(255, 255, 255, 0.07)";

/** The price a buyer pays today. With the launch price on, the full price stands before it, struck through. */
function Price() {
  return (
    <div className="flex flex-col items-center gap-3 md:items-start">
      <p className="flex items-baseline gap-4 font-medium tabular-nums leading-none tracking-[-0.02em]">
        {LAUNCH_PRICE_ACTIVE ? (
          <s className="text-4xl decoration-2 opacity-60 md:text-5xl">
            <span className="sr-only">Full price </span>
            {dollars(FULL_PRICE)}
          </s>
        ) : null}
        <span className="text-7xl md:text-8xl">
          {LAUNCH_PRICE_ACTIVE ? <span className="sr-only">Launch price </span> : null}
          {PRICE}
        </span>
      </p>
      {LAUNCH_PRICE_ACTIVE ? (
        <p aria-hidden="true" className="rounded-full bg-white/15 px-3 py-1 text-sm">
          Launch price
        </p>
      ) : null}
    </div>
  );
}

export async function Pricing() {
  const release = await getLatestRelease();
  return (
    <section id="pricing" className="mx-auto w-full max-w-[1120px] scroll-mt-20">
      <h2 className="sr-only">Pricing</h2>
      <div className="relative mx-auto mt-14 max-w-[880px] rounded-[20px] bg-gradient-to-br from-brand-light to-brand-deep text-white shadow-[0_32px_64px_-32px_rgba(27,85,194,0.55)] dark:shadow-[0_0_0_1px_rgba(255,255,255,0.16)] md:mt-10">
        <div aria-hidden="true" className="pointer-events-none absolute inset-0 overflow-hidden rounded-[inherit]">
          <div
            className="absolute inset-0 [mask-image:radial-gradient(ellipse_90%_45%_at_50%_0%,black_10%,transparent_75%)] md:[mask-image:radial-gradient(ellipse_60%_90%_at_82%_40%,black_10%,transparent_70%)]"
            style={{
              backgroundImage: `linear-gradient(${GRID_LINE} 1px, transparent 1px), linear-gradient(90deg, ${GRID_LINE} 1px, transparent 1px)`,
              backgroundSize: "32px 32px",
            }}
          />
          {/* On a narrow card the light ends above the first line of text, which needs the blue under it to be read. */}
          <div className="absolute left-1/2 top-0 size-[190px] -translate-x-1/2 -translate-y-1/2 bg-[radial-gradient(closest-side,rgba(160,205,255,0.5),transparent)] md:left-auto md:right-[-60px] md:top-0 md:size-[380px] lg:right-[-40px] lg:size-[520px] md:translate-x-0 md:-translate-y-[20%]" />
        </div>
        <div className="relative grid justify-items-center gap-8 px-6 pb-10 text-center md:grid-cols-[minmax(0,1fr)_auto] md:items-center md:justify-items-start md:gap-10 md:py-14 md:pl-14 md:pr-12 md:text-left">
          <div className="relative -mt-14 md:order-last md:-mt-24 md:self-start">
            <Image
              src="/icon-1024.png"
              alt=""
              width={1024}
              height={1024}
              sizes="(min-width: 1024px) 260px, (min-width: 768px) 200px, 120px"
              className="relative size-[120px] rotate-[5deg] drop-shadow-[0_18px_22px_rgba(6,24,74,0.5)] md:size-[200px] lg:size-[260px]"
            />
          </div>
          <div className="flex flex-col items-center gap-8 md:items-start">
            <div className="flex flex-col items-center gap-5 md:items-start">
              <div className="flex flex-col items-center gap-3 md:items-start">
                {release === null ? null : <p className="text-lg">Free for 7 days, then</p>}
                <Price />
              </div>
              {/* A line may end only where a sentence ends. */}
              <p className="text-lg">
                Pay&nbsp;once. Use&nbsp;it&nbsp;forever on&nbsp;up&nbsp;to&nbsp;{MACS}&nbsp;Macs
              </p>
            </div>
            <div className="flex flex-col items-center gap-4 md:items-start">
              <div className="flex flex-wrap items-center justify-center gap-3 md:justify-start">
                {release === null ? null : (
                  <DownloadButton release={release} placement="pricing" variant="brand">
                    <TryFree />
                  </DownloadButton>
                )}
                <BuyButton placement="pricing" variant={release === null ? "brand" : "brandOutline"}>
                  Buy Agent Caffeine for <span className="tabular-nums">{PRICE}</span>
                </BuyButton>
              </div>
              <p>1&nbsp;year&nbsp;of&nbsp;updates&nbsp;included. No&nbsp;subscription</p>
              <a href={PORTAL_URL} className="text-sm focus-visible:outline-white">
                Lost your key? Find it in your purchases
              </a>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
