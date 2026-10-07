import { agentsMoreThan } from "@/lib/agents";
import { PLANS, PRICE, dollars, macs } from "@/lib/pricing";
import { CONTACT_EMAIL, SITE_URL } from "@/lib/site";

export const dynamic = "force-static";

/** "A license key for 1 Mac costs $19." for each plan on offer. */
const KEYS = PLANS.map((plan) => `A license key for ${macs(plan)} costs ${dollars(plan)}.`).join(" ");

const TEXT = `# agent caffeine

> agent caffeine is a macOS menu bar app that keeps a Mac awake while AI coding agents work, also with the lid closed, and lets it sleep when they are idle or wait for you. It has a 7-day free trial, then costs ${PRICE} once, and runs on macOS 13 or later (Apple silicon and Intel).

- Detects more than ${agentsMoreThan} coding agents (Claude Code, Codex, Cursor, opencode, Gemini CLI and others). Claude Code, Codex and Cursor report their own state (working, waiting for you, or idle), and agent caffeine reads it on the Mac. It also watches the commands an agent started, so a build that is still busy keeps the Mac awake. Other agents are judged by signs of work, such as a running command or a write to the session file.
- An agent that waits for your answer keeps the Mac awake for 5 minutes, then the Mac can sleep. Idle sessions do not keep it awake in the default mode. The times can be changed in Preferences.
- Optional better detection: Claude Code, Codex, Cursor, Droid and opencode can report their state to agent caffeine directly. It is off until you switch it on per agent, and switching it off removes it again.
- Three modes: always, while an agent is open, or while an agent is working (the default).
- A closed lid on the power adapter works from the start. On battery it needs a small helper that you allow once in System Settings, and it turns on the \`SleepDisabled\` setting of macOS only while it holds the Mac awake.
- Safety: when the battery is at 20% (adjustable, or off) or the Mac gets too hot, it lets the Mac sleep and says why in a notification. After a battery stop it starts again at 25%, or when the Mac is plugged in. Do not put a working Mac in a closed bag. On battery the menu shows the charge and that level on one line.
- The built-in display dims as the lid closes and stays dark while the lid is closed. On a Mac with a lid angle sensor it dims from 45 degrees of lid opening down to closed, and gets bright again the same way when the lid opens.
- Pause for 30 minutes, 1 hour or until tomorrow. agent caffeine starts again by itself.
- Stay reachable for 1, 2 or 4 hours: the Mac stays awake until that time, also when no agent works, so a message from a phone (Claude Code Remote Control, Codex remote) reaches the agent. On battery with the lid closed it needs the helper, and it uses about 1% of battery per hour. A message cannot wake a Mac that sleeps.
- Notifications, each with its own switch: an agent is waiting for your answer (on by default), and an agent finished (off by default).
- Keyboard shortcuts that work in every app, with keys you choose: turn agent caffeine on or off, and pause for 1 hour.
- The menu bar icon can be hidden. The app keeps the Mac awake the same way without it.
- A 7-day free trial with every feature. It starts the first time the app opens and needs no account, no card and no key. After 7 days the app stops keeping the Mac awake until a license key is entered. The app and its settings stay.
- ${KEYS} Each is a one-time purchase with lifetime updates and no subscription. Deactivate a Mac in the app or in your Polar purchases to move the key to another.
- The app updates itself: it checks caffeinagent.com for updates and installs them when you agree.
- No telemetry and no analytics. It reads the process list, the state and session files of Claude Code, Codex and Cursor in \`~/.claude\`, \`~/.codex\` and \`~/.cursor/projects\`, and the battery level and lid angle, all on your own Mac. Its only network calls are the update check to caffeinagent.com and the license key check with Polar, which sends the key and the Mac's model. Nothing about you or your agents leaves the Mac.
- Sold by Mert Duzgun, an individual based in Antalya, Türkiye. Polar (polar.sh) is the merchant of record: it takes the payment, handles tax and sends the invoice. All sales are final, since the full app is free to try for 7 days first. Contact: ${CONTACT_EMAIL}.

## Links

- [Home](${SITE_URL}/): product, how it works, price, questions
- [The caffeinate command on Mac: every option, with examples](${SITE_URL}/blog/caffeinate-mac)
- [How to stop a Mac from sleeping, also with the lid closed](${SITE_URL}/blog/stop-mac-from-sleeping)
- [Privacy](${SITE_URL}/privacy): what the app, a purchase and the website collect
- [Terms](${SITE_URL}/terms): license, trial, payment, refunds and liability
`;

export function GET() {
  return new Response(TEXT, { headers: { "Content-Type": "text/plain; charset=utf-8" } });
}
