import { AgentsSection } from "@/components/agents-section";
import { Compare } from "@/components/compare";
import { Demo } from "@/components/demo";
import { Examples } from "@/components/examples";
import { Faq } from "@/components/faq";
import { Footer } from "@/components/footer";
import { Free } from "@/components/free";
import { Guides } from "@/components/guides";
import { Hero } from "@/components/hero";
import { JsonLd } from "@/components/json-ld";
import { SleepScenes } from "@/components/sleep-scenes";
import { SmallThings } from "@/components/small-things";
import { Support } from "@/components/support";
import { agentsMoreThan } from "@/lib/agents";
import { answerText, faqItems } from "@/lib/faq";
import { LICENSE_URL, ORGANIZATION, REPO_URL, SITE_URL } from "@/lib/site";

const structuredData = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "SoftwareApplication",
      name: "Agent Caffeine",
      operatingSystem: "macOS 13 or later",
      applicationCategory: "UtilitiesApplication",
      url: SITE_URL,
      image: `${SITE_URL}/icon.png`,
      description: `A macOS menu bar app that keeps the Mac awake while AI coding agents work, also with the lid closed, and lets it sleep when they are idle or wait for you. Detects Claude Code, Codex, opencode and more than ${agentsMoreThan} AI coding agents. Free and open source under the AGPL-3.0 license.`,
      featureList: [
        "Keeps the Mac awake while an AI coding agent works, also with the lid closed",
        "Lets the Mac sleep when agents are idle or wait for you",
        "Dims the built-in display as the lid closes and keeps it dark while the lid is closed",
        "Plays one short sound when the lid closes and the Mac stays awake",
        "Pause for 30 minutes, 1 hour or until tomorrow",
        "Stay reachable for 1, 2 or 4 hours, so a message from your phone reaches your agent",
        "Notifications when an agent waits for your answer or finishes",
        "Battery bar in the menu, and sleep at a battery level you set",
        "Command line tool and MCP server: a script, a long job or an agent can ask for the Mac to stay awake",
        "Keyboard shortcuts that work in every app",
        "The menu bar icon can be hidden",
      ],
      isAccessibleForFree: true,
      license: LICENSE_URL,
      sameAs: [REPO_URL],
      offers: { "@type": "Offer", price: 0, priceCurrency: "USD", url: SITE_URL },
    },
    {
      "@type": "FAQPage",
      mainEntity: faqItems().map((item) => ({
        "@type": "Question",
        name: item.question,
        acceptedAnswer: { "@type": "Answer", text: answerText(item.answer) },
      })),
    },
    ORGANIZATION,
    { "@type": "WebSite", name: "Agent Caffeine", url: SITE_URL },
  ],
};

export default function Home() {
  return (
    <main id="main" className="relative isolate flex min-h-screen flex-col gap-24 overflow-x-clip px-4 pt-14 md:px-6">
      <Hero />
      <Examples />
      <AgentsSection />
      <SleepScenes />
      <SmallThings />
      <Demo />
      <Compare />
      <Free />
      <Faq />
      <Guides />
      <Support />
      <Footer />
      <JsonLd data={structuredData} />
    </main>
  );
}
