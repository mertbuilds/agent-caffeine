import { AgentsSection } from "@/components/agents-section";
import { Faq } from "@/components/faq";
import { Footer } from "@/components/footer";
import { Hero } from "@/components/hero";
import { HowItWorks } from "@/components/how-it-works";
import { JsonLd } from "@/components/json-ld";
import { Pricing } from "@/components/pricing";
import { SleepScenes } from "@/components/sleep-scenes";
import { SmallThings } from "@/components/small-things";
import { agentsMoreThan } from "@/lib/agents";
import { answerText, faqItems } from "@/lib/faq";
import { PLANS, PRICE, macs } from "@/lib/pricing";
import { getLatestRelease } from "@/lib/release";
import { ORGANIZATION, SITE_URL } from "@/lib/site";

/** `trial` is whether there is a download, and so a free trial a reader can start. */
function structuredData(trial: boolean) {
  return {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "SoftwareApplication",
        name: "agent caffeine",
        operatingSystem: "macOS 13 or later",
        applicationCategory: "UtilitiesApplication",
        url: SITE_URL,
        image: `${SITE_URL}/icon.png`,
        description: `A macOS menu bar app that keeps the Mac awake while AI coding agents work, also with the lid closed, and lets it sleep when they are idle or wait for you. Detects Claude Code, Codex, opencode and more than ${agentsMoreThan} AI coding agents.${
          trial ? ` Free to download, with every feature for 7 days. After that it needs a license key, from ${PRICE} once.` : ""
        }`,
        featureList: [
          "Keeps the Mac awake while an AI coding agent works, also with the lid closed",
          "Lets the Mac sleep when agents are idle or wait for you",
          "Dims the built-in display as the lid closes and keeps it dark while the lid is closed",
          "Pause for 30 minutes, 1 hour or until tomorrow",
          "Stay reachable for 1, 2 or 4 hours, so a message from your phone reaches your agent",
          "Notifications when an agent waits for your answer or finishes",
          "Battery bar in the menu, and sleep at a battery level you set",
          "Keyboard shortcuts that work in every app",
          "The menu bar icon can be hidden",
        ],
        offers: PLANS.map((plan) => ({
          "@type": "Offer",
          name: `agent caffeine for ${macs(plan)}`,
          price: String(plan.price),
          priceCurrency: "USD",
          url: SITE_URL,
        })),
      },
      {
        "@type": "FAQPage",
        mainEntity: faqItems(trial).map((item) => ({
          "@type": "Question",
          name: item.question,
          acceptedAnswer: { "@type": "Answer", text: answerText(item.answer) },
        })),
      },
      ORGANIZATION,
      { "@type": "WebSite", name: "agent caffeine", url: SITE_URL },
    ],
  };
}

export default async function Home() {
  const trial = (await getLatestRelease()) !== null;
  return (
    <main className="relative isolate flex min-h-screen flex-col gap-24 overflow-x-clip px-4 pt-14 md:px-6">
      <Hero />
      <HowItWorks />
      <SleepScenes />
      <SmallThings />
      <AgentsSection />
      <Pricing />
      <Faq trial={trial} />
      <Footer />
      <JsonLd data={structuredData(trial)} />
    </main>
  );
}
