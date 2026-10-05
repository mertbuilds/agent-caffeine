import { MenuBarSimulator } from "@/components/menu-bar-simulator";
import { SectionHeading } from "@/components/section-heading";

export function HowItWorks() {
  return (
    <section id="how-it-works" className="mx-auto flex w-full max-w-[1120px] scroll-mt-20 flex-col items-center gap-12">
      <SectionHeading lead="Start an agent and see what agent caffeine does" title="How it works" />
      <MenuBarSimulator />
    </section>
  );
}
