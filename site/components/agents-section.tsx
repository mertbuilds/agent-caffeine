import { AgentsPanel } from "@/components/agents-panel";
import { detectedAgents } from "@/lib/agents";

export function AgentsSection() {
  return (
    <section className="mx-auto flex w-full max-w-[960px] flex-col items-center gap-8 text-center">
      <div className="flex max-w-[640px] flex-col gap-4">
        <h2 className="text-balance text-[1.75rem] font-medium leading-[1.2] tracking-[-0.01em]">
          Every agent you run
        </h2>
        <p className="text-pretty leading-relaxed text-muted">
          More than 40 agents are on the list. Add your own in Preferences
        </p>
      </div>
      <AgentsPanel />
      <p className="max-w-[26rem] text-balance text-sm leading-normal text-muted">
        A 581 kilobyte native Mac app. It lives in the menu bar and shows what it watches
      </p>
      <p className="max-w-[640px] text-pretty text-sm leading-relaxed text-muted">
        {detectedAgents.join(" · ")}
      </p>
    </section>
  );
}
