import Image from "next/image";
import Link from "next/link";
import { DownloadButton, DownloadForMac, DownloadNotReady } from "@/components/download-button";
import { BRAND_VARIANTS } from "@/components/pill";
import { getLatestRelease } from "@/lib/release";
import { REPO_URL } from "@/lib/site";

const GRID_LINE = "rgba(255, 255, 255, 0.07)";

/**
 * The blue card that says what the app costs: nothing. Its id stays `pricing`,
 * because the paid versions of the app open the page at `/#pricing`.
 */
export async function Free() {
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
            <div className="flex flex-col items-center gap-4 md:items-start">
              <h2 className="text-balance text-[2.5rem] font-medium leading-[1.05] tracking-[-0.02em] md:text-6xl">
                Free and open source
              </h2>
              {/* A line may end only where a sentence ends. */}
              <p className="text-lg">Every&nbsp;feature&nbsp;is&nbsp;free. No&nbsp;account,&nbsp;no&nbsp;card</p>
            </div>
            <div className="flex flex-col items-center gap-5 md:items-start">
              <div className="flex flex-wrap items-center justify-center gap-3 md:justify-start">
                {release === null ? (
                  <DownloadNotReady className="basis-full" />
                ) : (
                  <DownloadButton release={release} placement="pricing" variant="brand">
                    <DownloadForMac />
                  </DownloadButton>
                )}
                <a href={REPO_URL} className={BRAND_VARIANTS.brandOutline("large")}>
                  Source code
                </a>
              </div>
              <Link href="/#support" className="text-sm focus-visible:outline-white">
                Support the project
              </Link>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
