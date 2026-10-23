import type { Metadata } from "next";
import type { ReactNode } from "react";
import Link from "next/link";
import { COMPARE_LEAD } from "@/components/compare";
import { CompareSources, CompareTable } from "@/components/compare-table";
import { Footer } from "@/components/footer";
import { JsonLd } from "@/components/json-ld";
import { formatDate } from "@/lib/blog";
import { CHECKED_ON, OURS, TOOLS, type ToolId } from "@/lib/compare";
import { FULL_PRICE, LAUNCH_PRICE_ACTIVE, MACS, PRICE, dollars } from "@/lib/pricing";
import { AUTHOR, ORGANIZATION, SITE_URL } from "@/lib/site";

const title = "Agent Caffeine vs Adrafinil, Hold My Lid, LidRun and others";
const description =
  "Agent Caffeine next to Adrafinil, Hold My Lid, LidRun, Clamshell and Amphetamine: price, lid closed on battery, agent state and safety stops. With sources.";

export const metadata: Metadata = {
  title,
  description,
  alternates: { canonical: "/compare" },
  openGraph: { title, description, type: "article", url: "/compare", modifiedTime: CHECKED_ON, images: ["/og.png"] },
  twitter: { card: "summary_large_image", title, description, images: ["/og.png"] },
};

const structuredData = {
  "@context": "https://schema.org",
  "@type": "WebPage",
  name: title,
  description,
  url: `${SITE_URL}/compare`,
  dateModified: CHECKED_ON,
  author: AUTHOR,
  publisher: ORGANIZATION,
};

/** What each tool is good at and when to pick it, from the same pages as the table. */
const RIVALS: Record<Exclude<ToolId, "ours">, ReactNode> = {
  adrafinil: (
    <>
      <p>
        Adrafinil is free and open source (MIT). One installer sets up hooks for 9 agents: Claude Code, Codex,
        Cursor, Gemini CLI, Aider, Hermes, OpenCode, Cline and Pi. It keeps the Mac awake with the lid closed
        only while an agent works, and it stops when the Mac gets too hot under a closed lid. Its release
        notes also name a battery cutout, with no level.
      </p>
      <p>
        An agent can ask it for more time after its answer, through an MCP tool or a command, for example
        for a long build. Agent Caffeine has a command and an MCP server for this too. Adrafinil has
        one thing we do not have: it gives you the lines to add an agent of your own.
      </p>
      <p>
        For Claude Code it also knows when a session waits for you. A setting decides what happens then: the
        Mac stays awake, sleeps after a grace period, or sleeps at once. The menu shows what the session
        waits for.
      </p>
      <p>
        If you want a free tool and your agent is on that list, Adrafinil does the job. It needs macOS 26.4 or
        later. Its pages state a chime when you close the lid while it keeps the Mac awake, as Agent Caffeine
        has, and a summary when you open the lid. They do not state a notification when an agent finishes.
      </p>
    </>
  ),
  holdmylid: (
    <>
      <p>
        Hold My Lid costs $9.99 once for up to 3 Macs, and has a free trial. Its page calls $9.99 an early
        price and names $14.99 as the normal one. Its page gives two lists of the agents whose
        lifecycle hooks it reads. The answer in its FAQ names 3: Claude Code, Codex and OpenCode. The grid
        "Works out of the box" marks 7: those 3 and Gemini, Pi, Copilot CLI and Hermes. For others, such as
        Cursor, it checks the process. It runs on macOS 14 or later, on Apple
        silicon and Intel.
      </p>
      <p>
        It stops at a battery level you set, it has a mode that works only when the Mac is plugged in, and it
        sends a notification when your agents finish.
      </p>
      <p>
        If you want a mode that works only while the Mac is plugged in, pick Hold My Lid. Its pages do
        not state a stop for heat, a state for an agent that waits for you, or whether the closed lid on
        battery needs a helper.
      </p>
    </>
  ),
  lidrun: (
    <>
      <p>
        LidRun has a free plan that keeps the Mac awake with the lid open, with timers, a mode for charging
        only and a stop at a low battery. The closed lid and Auto Mode are in the paid plan, after a limited
        number of free closed-lid runs: $9.90 once for 1 Mac, $19.90 for 3 Macs, with a refund within 14 days.
      </p>
      <p>
        Auto Mode watches the processes of Claude Code, Cursor, Docker and Ollama. LidRun also has webhooks,
        it can run a command and let the Mac sleep when the command ends, and it keeps a log that says why a
        session started and stopped. It runs on macOS 13 or later, on Apple silicon and Intel.
      </p>
      <p>
        If you also leave Docker builds or local models running, or you want webhooks, pick LidRun. If the lid
        stays open, its free plan may be all you need. Its pages do not state that it reads the state an agent
        reports about itself.
      </p>
    </>
  ),
  clamshell: (
    <>
      <p>
        Clamshell keeps a MacBook awake with the lid closed, on power or on battery, with no admin rights, no
        helper and no sudo. No other tool on this page states that, and ours needs a helper for battery. It
        costs $9.99 once for 1 Mac or $19.99 for 3 Macs after a 7-day free trial, with a refund within 14
        days.
      </p>
      <p>
        Its page says that it does not detect agents. You arm it yourself: hold Option and close the lid. A
        script can also arm and disarm it. The stop for heat is always on, and the stop at a low battery is
        there when you turn it on.
      </p>
      <p>
        If you do not want to give a tool admin rights, or you want to decide yourself when the Mac stays
        awake, pick Clamshell. It runs only on Apple silicon laptops with macOS 14 or later.
      </p>
    </>
  ),
  amphetamine: (
    <>
      <p>
        Amphetamine is free on the Mac App Store, with no in-app purchases. It is a keep-awake tool for
        general use, with many triggers: an app that runs, a Wi-Fi network, a display or a drive that is
        connected, the charger, processor use.
      </p>
      <p>
        It can keep a MacBook awake with the lid closed, and it can end a session when the battery is low.
        Its listing names no AI coding agents. The nearest trigger keeps the Mac awake while an app you pick
        is running. The latest version on the listing is 5.3.2, from November 10, 2023.
      </p>
      <p>
        If you want a free tool for more than agents, such as downloads, a presentation or a Mac that must
        stay awake on one network, pick Amphetamine. We wrote more about it in{" "}
        <Link href="/blog/amphetamine-mac">our guide to Amphetamine</Link>.
      </p>
    </>
  ),
};

export default function ComparePage() {
  return (
    <main id="main" className="relative isolate flex min-h-screen flex-col gap-12 overflow-x-clip px-4 pt-[6.5rem] md:px-6">
      <header className="mx-auto flex w-full max-w-[680px] flex-col gap-4">
        <h1 className="text-balance text-[2rem] font-medium leading-[1.15] tracking-[-0.01em] md:text-[2.5rem]">
          How Agent Caffeine compares
        </h1>
        <p className="text-pretty leading-relaxed text-muted">{COMPARE_LEAD}.</p>
        <p className="text-sm text-muted">
          Checked on <time dateTime={CHECKED_ON}>{formatDate(CHECKED_ON)}</time>
        </p>
      </header>
      <section aria-label="The table" className="mx-auto flex w-full min-w-0 max-w-[1120px] flex-col gap-4">
        <CompareTable />
        <CompareSources />
      </section>
      <article className="mx-auto flex w-full min-w-0 max-w-[680px] flex-col gap-10">
        <div className="article">
          <div>
            <h2>What you get for the price</h2>
            <p>
              Agent Caffeine costs {PRICE} once for up to {MACS} Macs
              {LAUNCH_PRICE_ACTIVE ? ` at the launch price, then ${dollars(FULL_PRICE)},` : ","} after a 7-day free
              trial. Two other tools on this page are free, and one has a free plan for the lid open. Many of
              them also keep a Mac awake with the lid closed on battery, read the hooks of an agent, or stop for
              a low battery or heat.
            </p>
            <p>
              What we put together in one app: the state of each agent, also when it waits for you, the closed
              lid on battery, a stop at a low battery, a stop for heat, and a notification when an agent needs
              you or finishes. As far as the pages of the other tools say, none of them states all of these.
              Their pages can be silent about a thing the tool does, so read their pages too.
            </p>
            {TOOLS.filter((tool) => tool.id !== OURS).map((tool) => (
              <section key={tool.id} id={tool.id}>
                <h2>{tool.name}</h2>
                {RIVALS[tool.id as Exclude<ToolId, "ours">]}
                <p>
                  Sources:{" "}
                  {tool.sources.map((source, index) => (
                    <span key={source.url}>
                      {index > 0 ? ", " : null}
                      <a href={source.url} rel="noreferrer">
                        {source.label}
                      </a>
                    </span>
                  ))}
                  .
                </p>
              </section>
            ))}
            <h2>The caffeinate command</h2>
            <p>
              <code>caffeinate</code> comes with macOS and is free. It keeps the Mac awake until a time you
              give or until a process ends. Its manual says that the option that prevents system sleep is
              valid only on AC power, and it lists no option for agents, the battery level or heat (
              <a href="https://ss64.com/mac/caffeinate.html" rel="noreferrer">
                a copy of the manual
              </a>
              ). If one command in one terminal is all you run, it may be enough. We wrote more in{" "}
              <Link href="/blog/caffeinate-mac">our guide to caffeinate</Link>.
            </p>
          </div>
        </div>
      </article>
      <Footer />
      <JsonLd data={structuredData} />
    </main>
  );
}
