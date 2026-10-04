import { AgentsSection } from "@/components/agents-section";
import { Faq } from "@/components/faq";
import { Footer } from "@/components/footer";
import { Header } from "@/components/header";
import { Hero } from "@/components/hero";
import { HowItWorks } from "@/components/how-it-works";
import { Pricing } from "@/components/pricing";
import { WithoutSection } from "@/components/without-section";

export default function Home() {
  return (
    <main className="relative isolate flex min-h-screen flex-col gap-24 overflow-x-clip px-4 md:px-6">
      <div className="flex flex-col">
        <Header />
        <Hero />
      </div>
      <WithoutSection />
      <section className="mx-auto flex w-full max-w-[960px] flex-col gap-12">
        <div className="mx-auto flex max-w-[640px] flex-col gap-4 text-center">
          <h2 className="text-balance text-[1.75rem] font-medium leading-[1.2] tracking-[-0.01em]">
            How it works
          </h2>
          <p className="text-pretty leading-relaxed text-muted">
            It watches your agents, so you do not have to remember
          </p>
        </div>
        <HowItWorks />
      </section>
      <AgentsSection />
      <Pricing />
      <Faq />
      <Footer />
    </main>
  );
}
