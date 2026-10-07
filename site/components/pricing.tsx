import Image from "next/image";
import { DownloadButton, TryFree } from "@/components/download-button";
import { PlanCard } from "@/components/plan-card";
import { getLatestRelease } from "@/lib/release";

const GRID_LINE = "rgba(255, 255, 255, 0.07)";

/** From the download to the menu bar. */
const STEPS = ["Download and open the file", "Drag agent caffeine to Applications", "Open it. The robot appears in your menu bar"];

export async function Pricing() {
  const release = await getLatestRelease();
  return (
    <section id="pricing" className="mx-auto w-full max-w-[1120px] scroll-mt-20">
      <div className="relative mx-auto mt-14 max-w-[880px] rounded-[20px] bg-gradient-to-br from-brand-light to-brand-deep text-white shadow-[0_32px_64px_-32px_rgba(27,85,194,0.55)] dark:shadow-[0_0_0_1px_rgba(255,255,255,0.16)] md:mt-10">
        <div aria-hidden="true" className="pointer-events-none absolute inset-0 overflow-hidden rounded-[inherit]">
          <div
            className="absolute inset-0 [mask-image:radial-gradient(ellipse_90%_45%_at_50%_0%,black_10%,transparent_75%)] md:[mask-image:radial-gradient(ellipse_60%_90%_at_82%_40%,black_10%,transparent_70%)]"
            style={{
              backgroundImage: `linear-gradient(${GRID_LINE} 1px, transparent 1px), linear-gradient(90deg, ${GRID_LINE} 1px, transparent 1px)`,
              backgroundSize: "32px 32px",
            }}
          />
          <div className="absolute left-1/2 top-0 size-[320px] -translate-x-1/2 -translate-y-1/3 bg-[radial-gradient(closest-side,rgba(160,205,255,0.5),transparent)] md:left-auto md:right-[-60px] md:top-0 md:size-[380px] lg:right-[-40px] lg:size-[520px] md:translate-x-0 md:-translate-y-[20%]" />
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
          <PlanCard
            download={
              release === null ? null : (
                <DownloadButton release={release} placement="pricing" variant="brand">
                  <TryFree />
                </DownloadButton>
              )
            }
          />
        </div>
      </div>
      <div className="mx-auto mt-8 flex max-w-[880px] flex-col gap-4 px-2 text-sm">
        <ol className="grid gap-x-6 gap-y-3 sm:grid-cols-3">
          {STEPS.map((step, index) => (
            <li key={step} className="flex items-baseline gap-2.5">
              <span aria-hidden="true" className="flex size-5 shrink-0 items-center justify-center self-start rounded-full border border-border text-xs tabular-nums text-muted">
                {index + 1}
              </span>
              <span className="text-pretty leading-5">{step}</span>
            </li>
          ))}
        </ol>
        <p className="text-pretty text-muted">macOS 13 or later, Apple silicon and Intel · Signed and notarized by Apple</p>
      </div>
    </section>
  );
}
