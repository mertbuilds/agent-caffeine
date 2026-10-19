import type { Metadata } from "next";
import Link from "next/link";
import type { CSSProperties } from "react";
import { PILL, SIZES } from "@/components/pill";
import { Footer } from "@/components/footer";

export const metadata: Metadata = { title: "Page not found · Agent Caffeine" };

/** Each z's place and size when nothing moves: a stair that rises and fades off the robot. */
const SNORES = [
  { still: "translate(3px, -5px) scale(0.7)", stillOpacity: 0.9 },
  { still: "translate(13px, -21px) scale(0.95)", stillOpacity: 0.65 },
  { still: "translate(24px, -37px) scale(1.2)", stillOpacity: 0.4 },
];
const SNORE_PERIOD = 7.2;

/** The menu bar icon's head (components/menu-icon.tsx) drawn as a line at five times its size, its eyes shut. */
function SleepingRobot() {
  return (
    <svg aria-hidden="true" className="h-auto w-[168px] max-w-full overflow-visible text-fg" fill="none" viewBox="0 0 168 144">
      <g stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.5">
        <circle cx="72" cy="41" r="5" />
        <path d="M72 46v10" />
        <rect height="64" rx="27" width="80" x="32" y="56" />
        <path d="M32 72h-4a4 4 0 0 0-4 4v12a4 4 0 0 0 4 4h4M112 72h4a4 4 0 0 1 4 4v12a4 4 0 0 1-4 4h-4" />
        <path d="M50.5 89q7 6 14 0M79.5 89q7 6 14 0" />
      </g>
      <g className="text-muted" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.5">
        {SNORES.map((snore, index) => {
          const delay = `${-index * (SNORE_PERIOD / SNORES.length)}s`;
          return (
            <g key={index} transform="translate(118 50)">
              <g className="snore-sway" style={{ animationDelay: delay }}>
                <path
                  className="snore-rise"
                  d="M-5-5h10l-10 10h10"
                  style={{ animationDelay: delay, "--snore-still": snore.still, "--snore-still-opacity": snore.stillOpacity } as CSSProperties}
                />
              </g>
            </g>
          );
        })}
      </g>
    </svg>
  );
}

export default function NotFound() {
  return (
    <main id="main" className="relative isolate flex min-h-screen flex-col gap-12 overflow-x-clip px-4 pt-[6.5rem] md:px-6">
      <div className="mx-auto flex w-full max-w-[680px] flex-1 flex-col items-center justify-center gap-10 pb-12 text-center">
        <SleepingRobot />
        <div className="flex flex-col items-center gap-3">
          <h1 className="text-balance text-[2rem] font-medium leading-[1.15] tracking-[-0.01em] md:text-[2.5rem]">
            This page fell asleep
          </h1>
          <p className="max-w-[26rem] text-pretty leading-relaxed text-muted">
            Nothing runs at this address. It may have moved, or the link is wrong.
          </p>
        </div>
        <Link href="/" className={`${PILL} bg-fg text-bg ${SIZES.small}`}>
          Go to the home page
        </Link>
      </div>
      <Footer />
    </main>
  );
}
