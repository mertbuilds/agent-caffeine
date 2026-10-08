import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Hero, type HeroVariant } from "@/components/hero";

export const metadata: Metadata = { robots: { index: false, follow: false } };

const VARIANTS: readonly { letter: string; variant: HeroVariant; name: string }[] = [
  { letter: "A", variant: "a", name: "App in front" },
  { letter: "B", variant: "b", name: "Pack and go" },
  { letter: "C", variant: "c", name: "Both" },
  { letter: "Z", variant: "z", name: "The hero before" },
];

/**
 * The heroes side by side, each whole and at its real size, to pick one by
 * its letter. Only the dev server draws it: a production build answers with
 * "not found".
 */
export default function HeroLab() {
  if (process.env.NODE_ENV !== "development") notFound();
  return (
    <main id="main" className="relative isolate flex min-h-screen flex-col overflow-x-clip px-4 pt-14 md:px-6">
      {VARIANTS.map((entry) => (
        <div key={entry.letter} id={entry.letter} className="border-b border-border">
          <p className="mx-auto flex w-full max-w-[1120px] items-baseline gap-4 pt-10">
            <span className="text-[4rem] font-medium leading-none">{entry.letter}</span>
            <span className="text-lg text-muted">{entry.name}</span>
          </p>
          <Hero variant={entry.variant} />
        </div>
      ))}
    </main>
  );
}
