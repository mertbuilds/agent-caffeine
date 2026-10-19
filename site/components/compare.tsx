import Link from "next/link";
import { CompareSources, CompareTable } from "@/components/compare-table";
import { SectionHeading } from "@/components/section-heading";

export const COMPARE_LEAD =
  "Agent Caffeine follows what each agent is doing, and stops for a low battery or heat. It is free and open source, and some of the other tools here are free too";

export function Compare() {
  return (
    <section id="compare" className="mx-auto flex w-full max-w-[1120px] scroll-mt-20 flex-col gap-10">
      <SectionHeading lead={COMPARE_LEAD} title="How it compares" />
      <div className="flex min-w-0 flex-col gap-4">
        <CompareTable />
        <CompareSources />
        <p className="text-sm">
          <Link href="/compare">When to pick another tool instead</Link>
        </p>
      </div>
    </section>
  );
}
