import { MenuBarSimulator } from "@/components/menu-bar-simulator";
import { SectionHeading } from "@/components/section-heading";

export function Demo() {
  return (
    <section id="demo" className="relative mx-auto flex w-full max-w-[1120px] scroll-mt-20 flex-col items-center gap-12">
      {/* The name this section had, for a link that still has it. */}
      <span aria-hidden="true" className="absolute top-0 scroll-mt-20" id="how-it-works" />
      <SectionHeading lead="Pick a situation and see what Agent Caffeine does" title="Demo" />
      <MenuBarSimulator />
    </section>
  );
}
