import { AgentsSection } from "@/components/agents-section";
import { Faq } from "@/components/faq";
import { Footer } from "@/components/footer";
import { Header } from "@/components/header";
import { Hero } from "@/components/hero";
import { HowItWorks } from "@/components/how-it-works";
import { JsonLd } from "@/components/json-ld";
import { Pricing } from "@/components/pricing";
import { agentsMoreThan } from "@/lib/agents";
import { answerText, faqItems } from "@/lib/faq";
import { ORGANIZATION, SITE_URL } from "@/lib/site";

const structuredData = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "SoftwareApplication",
      name: "agent caffeine",
      operatingSystem: "macOS 13 or later",
      applicationCategory: "UtilitiesApplication",
      url: SITE_URL,
      image: `${SITE_URL}/icon.png`,
      description: `A macOS menu bar app that keeps the Mac awake while AI coding agents work, also with the lid closed, and lets it sleep when they are idle. Detects Claude Code, Codex, OpenCode and more than ${agentsMoreThan} AI coding agents.`,
      offers: { "@type": "Offer", price: "9", priceCurrency: "USD" },
    },
    {
      "@type": "FAQPage",
      mainEntity: faqItems.map((item) => ({
        "@type": "Question",
        name: item.question,
        acceptedAnswer: { "@type": "Answer", text: answerText(item.answer) },
      })),
    },
    ORGANIZATION,
    { "@type": "WebSite", name: "agent caffeine", url: SITE_URL },
  ],
};

export default function Home() {
  return (
    <main className="relative isolate flex min-h-screen flex-col gap-24 overflow-x-clip px-4 md:px-6">
      <div className="flex flex-col">
        <Header />
        <Hero />
      </div>
      <HowItWorks />
      <AgentsSection />
      <Pricing />
      <Faq />
      <Footer />
      <JsonLd data={structuredData} />
    </main>
  );
}
