import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { PRICE } from "@/lib/pricing";

export const metadata: Metadata = { robots: { index: false, follow: false } };

const GRID_LINE = "rgba(255, 255, 255, 0.06)";

/**
 * The picture for link previews, 1200 by 630, in the dark look of the page.
 * Only the dev server draws it: `scripts/og-image.sh` takes its picture and
 * saves it as `public/og.png`. A production build answers with "not found".
 */
export default function OgImage() {
  if (process.env.NODE_ENV !== "development") notFound();
  return (
    <main id="main" className="fixed left-0 top-0 z-50 flex h-[630px] w-[1200px] items-center overflow-hidden bg-black px-20 text-white">
      <div
        aria-hidden="true"
        className="absolute inset-0 [mask-image:radial-gradient(ellipse_55%_85%_at_80%_48%,black_10%,transparent_75%)]"
        style={{
          backgroundImage: `linear-gradient(${GRID_LINE} 1px, transparent 1px), linear-gradient(90deg, ${GRID_LINE} 1px, transparent 1px)`,
          backgroundSize: "40px 40px",
        }}
      />
      <div aria-hidden="true" className="absolute right-[-60px] top-1/2 size-[640px] -translate-y-1/2 bg-[radial-gradient(closest-side,rgba(42,112,224,0.55),transparent)]" />
      <div className="relative flex flex-col gap-10">
        <p className="flex items-center gap-4 text-[30px] leading-none text-[#a3a3a3]">
          <img alt="" className="size-11" height={44} src="/icon.png" width={44} />
          Agent Caffeine
        </p>
        <h1 className="text-[76px] font-medium leading-[1.06] tracking-[-0.02em]">
          Close your Mac
          <br />
          <span className="text-[#5aa2ff]">with no worry</span>
        </h1>
        <p className="text-[34px] leading-none text-[#a3a3a3]">Free for 7 days, then {PRICE} once</p>
      </div>
      <img
        alt=""
        className="absolute right-[70px] top-1/2 size-[380px] -translate-y-1/2 rotate-[5deg] drop-shadow-[0_24px_32px_rgba(6,24,74,0.6)]"
        height={380}
        src="/icon-1024.png"
        width={380}
      />
    </main>
  );
}
