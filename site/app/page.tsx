import Link from "next/link";
import { BuyCta, OutboundLink } from "@/components/track";

const BUY_URL =
  process.env.NEXT_PUBLIC_BUY_URL ??
  "https://buy.polar.sh/polar_cl_UtPTTZP0j4vXcUW47KZQalB2aVkSo3GyKubce3pvdr1";

const detectedAgents = [
  "Claude Code", "Codex", "Opencode", "Cursor agent", "Gemini CLI", "Aider",
  "Amp", "Crush", "Goose", "Cline", "Windsurf", "Openhands", "Forgecode",
  "Junie", "Roo Code", "Tabnine CLI", "Zencoder", "Trae", "Qwen Code",
  "Qoder", "Continue", "Codebuddy", "Codestudio", "Codemaker",
  "Antigravity", "Mistral Vibe", "Devin", "Droid", "Augment", "Firebender",
  "Hermes", "Iflow", "Kilo", "Kiro CLI", "Mcpjam", "Pochi", "Rovodev",
  "Deepagents", "Neovate", "Command Code", "+ user-editable allowlist",
];

export default function Home() {
  return (
    <main className="min-h-screen px-6 md:px-10">
      <Header />
      <Hero />
      <ProblemSection />
      <HowItWorks />
      <AgentsGrid />
      <Pricing />
      <Faq />
      <Footer />
    </main>
  );
}

function Header() {
  return (
    <header className="mx-auto flex max-w-5xl items-center justify-between py-6 text-sm">
      <div className="flex items-center gap-2 font-mono">
        <CoffeeIcon />
        <span>agent caffeine</span>
      </div>
      <BuyCta
        href={BUY_URL}
        placement="header"
        className="rounded-full bg-ink px-4 py-1.5 text-paper hover:bg-accent transition"
      >
        buy · $9
      </BuyCta>
    </header>
  );
}

function CoffeeIcon({ className = "" }: { className?: string }) {
  // styled after sf symbol "cup.and.saucer.fill" — same icon the mac menu bar uses
  return (
    <svg
      viewBox="0 0 24 24"
      width="18"
      height="18"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className={className}
      aria-hidden="true"
    >
      <path
        d="M5 7h11v4a5.5 5.5 0 0 1-5.5 5.5h0A5.5 5.5 0 0 1 5 11V7Z"
        fill="currentColor"
        className="text-accent"
      />
      <path
        d="M16 8.5h1.25a2.75 2.75 0 0 1 0 5.5H16"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        className="text-accent"
      />
      <path
        d="M4 18.5h13"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        className="text-accent"
      />
    </svg>
  );
}

function Hero() {
  return (
    <section className="mx-auto max-w-7xl pt-12 md:pt-20 pb-16 md:pb-24">
      <div className="grid md:grid-cols-12 gap-10 md:gap-12 items-center">
        <div className="md:col-span-6">
          <h1 className="text-3xl md:text-[2.5rem] font-bold leading-[1.15] tracking-tight">
            keep your mac awake.
            <br />
            only while your agents are working.
            <br />
            <span className="text-accent">even with the lid closed.</span>
          </h1>
          <div className="mt-8 flex flex-col sm:flex-row gap-3 items-start sm:items-center">
            <BuyCta
              href={BUY_URL}
              placement="hero"
              className="inline-block rounded-full bg-ink px-7 py-3 text-paper font-medium hover:bg-accent transition"
            >
              buy agent caffeine · $9
            </BuyCta>
            <p className="text-xs text-ink/55 font-mono">
              macos 13+ · signed · notarized
            </p>
          </div>
        </div>

        <div className="md:col-span-6 flex justify-center md:justify-end">
          <OutboundLink
            href="https://twitter.com/OpenAIDevs/status/2054973436280418521"
            event="poster_clicked"
            props={{ tweet: "openaidevs_lid" }}
            className="block w-full max-w-[520px] md:max-w-none rounded-2xl overflow-hidden border border-ink/10 shadow-xl shadow-ink/10 hover:shadow-2xl transition"
          >
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src="/laptop-on-copier.jpg"
              alt="a macbook propped open on a xerox photocopier so the lid doesn't close"
              width={1600}
              height={854}
              className="block w-full h-auto"
            />
          </OutboundLink>
        </div>
      </div>

      <div className="mt-16 md:mt-20 mx-auto max-w-2xl flex flex-col items-center">
        <AppShot />
        <p className="mt-5 text-center text-sm text-ink/60 max-w-sm leading-relaxed">
          a 418 kB native mac app. light as air. lives next to your wifi
          icon. shows what it&apos;s watching and whether it&apos;s holding
          the mac awake.
        </p>
      </div>
    </section>
  );
}

function AppShot() {
  return (
    <div className="rounded-2xl border border-ink/10 bg-gradient-to-b from-white to-cream p-5 shadow-2xl shadow-ink/10">
      <div className="flex items-center justify-between mb-3">
        <span className="font-bold">agent caffeine</span>
        <Toggle />
      </div>
      <p className="text-sm text-ink/70 mb-3">keeping mac awake</p>
      <Divider />
      <AgentRow color="green" name="opencode" sub="CLI · active" time="now" />
      <AgentRow color="green" name="wiki · landing page" sub="Claude Code · active" time="now" />
      <AgentRow color="yellow" name="claudemarketplaces.com" sub="Claude Code · waitingForInput" time="14s" />
      <Divider />
      <div className="flex justify-between text-xs text-ink/50 pt-2">
        <span>preferences…</span>
        <span>quit</span>
      </div>
    </div>
  );
}

function Toggle() {
  return (
    <div className="h-5 w-9 rounded-full bg-accent flex items-center justify-end px-0.5">
      <div className="h-4 w-4 rounded-full bg-white" />
    </div>
  );
}

function AgentRow({ color, name, sub, time }: { color: "green" | "yellow" | "gray"; name: string; sub: string; time: string }) {
  const dotColor = { green: "bg-green-500", yellow: "bg-yellow-400", gray: "bg-gray-300" }[color];
  return (
    <div className="flex items-center gap-3 py-2">
      <span className={`h-2 w-2 rounded-full ${dotColor}`} />
      <div className="flex-1 min-w-0">
        <div className="text-sm truncate">{name}</div>
        <div className="text-[10px] text-ink/50">{sub}</div>
      </div>
      <span className="text-[10px] text-ink/40 font-mono">{time}</span>
    </div>
  );
}

function Divider() {
  return <div className="h-px bg-ink/10 my-2" />;
}

function ProblemSection() {
  return (
    <section className="mx-auto max-w-5xl py-16 md:py-24 border-t border-ink/10">
      <div className="grid md:grid-cols-2 gap-10 md:gap-16 items-start">
        <div>
          <p className="font-mono text-xs uppercase tracking-widest text-accent mb-4">
            what happens otherwise
          </p>
          <h2 className="text-3xl md:text-4xl font-bold leading-tight">
            the lid clicks shut.
            <br />
            everything dies.
          </h2>
          <p className="mt-6 text-ink/70 leading-relaxed">
            no caffeinate. no half-open lid. just a forgotten lid-close on
            battery. macos clamshell-sleeps the whole machine. the agent
            loses its socket. the model loses the turn. you come back to a
            dead terminal and 20 minutes of inference billed to nothing.
          </p>
        </div>

        <div className="rounded-2xl border border-ink/10 bg-ink/5 p-6 font-mono text-xs leading-relaxed text-ink/80">
          <div className="space-y-1">
            <div>$ claude</div>
            <div className="text-ink/50">{`> refactor the entire auth module`}</div>
            <div className="text-ink/50">working...</div>
            <div className="text-ink/50">{`  edited 14 files`}</div>
            <div className="text-ink/50">{`  running tests...`}</div>
            <div className="text-ink/30 italic mt-2">[ lid closes ]</div>
            <div className="text-ink/30 italic">[ battery: clamshell sleep ]</div>
            <div className="text-red-700 mt-2">connection lost</div>
            <div className="text-red-700">session terminated</div>
            <div className="text-ink/40 mt-2">$ _</div>
          </div>
        </div>
      </div>
    </section>
  );
}

function HowItWorks() {
  const points = [
    {
      n: "01",
      h: "watches claude code",
      p: "spots running claude sessions via the process list, plus the session files at ~/.claude/projects for per-session detail.",
    },
    {
      n: "02",
      h: "watches your agent processes",
      p: "polls the process list every 5 seconds against a user-editable allowlist. 40+ known cli agents preloaded.",
    },
    {
      n: "03",
      h: "holds the mac awake on ac power",
      p: "uses iopmassertion preventsystemsleep. lid closes, machine stays alive, agent keeps thinking.",
    },
    {
      n: "04",
      h: "overrides on battery, optionally",
      p: "one-time admin prompt installs a scoped sudoers entry, then agent caffeine toggles pmset disablesleep only while an agent is mid-run.",
    },
    {
      n: "05",
      h: "lets the mac sleep when done",
      p: "the moment no agent is left running, the assertion releases. battery saved.",
    },
  ];
  return (
    <section className="mx-auto max-w-5xl py-16 md:py-24 border-t border-ink/10">
      <p className="font-mono text-xs uppercase tracking-widest text-accent mb-4">
        how it works
      </p>
      <h2 className="text-3xl md:text-4xl font-bold leading-tight mb-12">
        agent-aware, not just a coffee cup.
      </h2>
      <div className="grid md:grid-cols-2 gap-x-12 gap-y-10">
        {points.map((pt) => (
          <div key={pt.n} className="flex gap-5">
            <span className="font-mono text-xs text-accent pt-1 shrink-0">{pt.n}</span>
            <div>
              <h3 className="font-bold text-lg mb-2">{pt.h}</h3>
              <p className="text-ink/70 leading-relaxed">{pt.p}</p>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

function AgentsGrid() {
  return (
    <section className="mx-auto max-w-5xl py-16 md:py-24 border-t border-ink/10">
      <p className="font-mono text-xs uppercase tracking-widest text-accent mb-4">
        detects
      </p>
      <h2 className="text-3xl md:text-4xl font-bold mb-4">
        every agent you run.
      </h2>
      <p className="text-ink/70 mb-10 max-w-2xl leading-relaxed">
        40+ cli agents preloaded. add your own in seconds.
      </p>
      <div className="flex flex-wrap gap-2">
        {detectedAgents.map((a) => (
          <span
            key={a}
            className="rounded-full bg-ink/5 px-3 py-1.5 text-sm border border-ink/10"
          >
            {a}
          </span>
        ))}
      </div>
    </section>
  );
}

function Pricing() {
  return (
    <section className="mx-auto max-w-5xl py-16 md:py-24 border-t border-ink/10">
      <div className="rounded-3xl bg-ink text-paper p-10 md:p-16 text-center">
        <p className="font-mono text-xs uppercase tracking-widest text-accent/80 mb-4">
          one price
        </p>
        <p className="text-7xl md:text-8xl font-bold">$9</p>
        <p className="mt-4 text-paper/70 max-w-md mx-auto">
          once. lifetime updates. no subscription.
        </p>
        <BuyCta
          href={BUY_URL}
          placement="pricing"
          className="mt-8 inline-block rounded-full bg-paper text-ink px-7 py-3 font-medium hover:bg-accent hover:text-paper transition"
        >
          buy agent caffeine
        </BuyCta>
        <p className="mt-4 text-xs text-paper/50">
          signed · notarized · gatekeeper-clean
        </p>
      </div>
    </section>
  );
}

function Faq() {
  const items = [
    {
      q: "does it really work with the lid closed on battery?",
      a: "yes. lid closed on ac power works out of the box via iopmassertion. lid closed on battery also works once you grant the one-time sudoers install, after which agent caffeine toggles pmset disablesleep only while an agent is running. both paths, every chip.",
    },
    {
      q: "what privacy concerns are there?",
      a: "no network calls. no telemetry. agent caffeine reads files inside ~/.claude/projects and scans process names on your own machine. that’s the entire footprint.",
    },
    {
      q: "what macos versions?",
      a: "macos 13 ventura or later. universal binary, runs natively on apple silicon and intel.",
    },
    {
      q: "do i need to install a privileged helper or weird permissions?",
      a: "only if you want the on-battery override. otherwise: no daemons, no helpers. just a menu bar app and an iopmassertion.",
    },
    {
      q: "what if my agent isn’t in the default list?",
      a: "open preferences. type the process name. it’s a simple allowlist you control.",
    },
  ];
  return (
    <section className="mx-auto max-w-3xl py-16 md:py-24 border-t border-ink/10">
      <p className="font-mono text-xs uppercase tracking-widest text-accent mb-4">faq</p>
      <h2 className="text-3xl md:text-4xl font-bold mb-10">questions.</h2>
      <div className="space-y-6">
        {items.map((it) => (
          <div key={it.q}>
            <h3 className="font-bold mb-2">{it.q}</h3>
            <p className="text-ink/70 leading-relaxed">{it.a}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

function Footer() {
  return (
    <footer className="mx-auto max-w-5xl py-10 border-t border-ink/10 text-sm text-ink/50 flex flex-col md:flex-row justify-between items-center gap-2">
      <span className="font-mono">agent caffeine · 2026</span>
      <span>
        made by{" "}
        <Link href="https://x.com/mertduzgun" className="underline hover:text-accent">
          @mertduzgun
        </Link>
      </span>
    </footer>
  );
}
