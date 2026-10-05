"use client";

import { useRef } from "react";
import { AgentIcon } from "@/components/agent-icons";
import { SectionHeading } from "@/components/section-heading";
import { agents, agentsMoreThan } from "@/lib/agents";
import { useSeen } from "@/lib/use-seen";

type Agent = (typeof agents)[number];

/** Agents with and without a mark, spread evenly through each other. */
function mixed(): Agent[] {
  const marked = agents.filter((agent) => agent.icon !== undefined);
  const unmarked = agents.filter((agent) => agent.icon === undefined);
  const place = (group: Agent[]) =>
    group.map((agent, index) => ({ agent, at: (index + 0.5) / group.length }));
  return [...place(marked), ...place(unmarked)]
    .sort((a, b) => a.at - b.at)
    .map(({ agent }) => agent);
}

const MIXED = mixed();
const ROWS = [
  MIXED.filter((_, index) => index % 2 === 0),
  MIXED.filter((_, index) => index % 2 === 1),
];

function Chip({ agent }: { agent: Agent }) {
  return (
    <li className="flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-lg border border-border px-3 py-1.5 text-sm">
      {agent.icon === undefined ? null : <AgentIcon className="size-4 shrink-0" name={agent.icon} />}
      {agent.name}
    </li>
  );
}

export function AgentsSection() {
  const ref = useRef<HTMLDivElement>(null);
  const seen = useSeen(ref, 0);

  return (
    <section className="flex flex-col gap-10">
      <SectionHeading
        lead={`More than ${agentsMoreThan} agents, and you can add your own`}
        title="It knows your agents"
      />
      <div ref={ref} className={`agent-marquee -mx-4 md:-mx-6 ${seen ? "" : "agent-marquee-paused"}`}>
        <ul className="agent-list mx-auto flex max-w-[1120px] flex-wrap justify-center gap-2">
          {agents.map((agent) => (
            <Chip key={agent.name} agent={agent} />
          ))}
        </ul>
        {ROWS.map((row, index) => (
          <div key={index} aria-hidden="true" className="agent-row">
            <div className={`agent-track ${index === 1 ? "agent-track-back" : ""}`}>
              {[0, 1].map((copy) => (
                <ul key={copy} className="flex gap-2 pr-2">
                  {row.map((agent) => (
                    <Chip key={agent.name} agent={agent} />
                  ))}
                </ul>
              ))}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
