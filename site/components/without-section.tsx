import { WithoutDrawing } from "@/components/drawings/without-drawing";

export function WithoutSection() {
  return (
    <section className="mx-auto grid w-full max-w-[960px] items-center gap-12 md:grid-cols-2">
      <div className="flex flex-col gap-4">
        <h2 className="text-balance text-[1.75rem] font-medium leading-[1.2] tracking-[-0.01em]">
          Close the lid and the work stops
        </h2>
        <p className="max-w-[640px] text-pretty leading-relaxed text-muted">
          macOS puts the whole machine to sleep. The agent loses its connection. You come back to a
          dead terminal and twenty minutes of work lost.
        </p>
      </div>
      <WithoutDrawing />
    </section>
  );
}
