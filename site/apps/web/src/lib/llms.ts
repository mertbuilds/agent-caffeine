import { agentsMoreThan } from './agents.ts';
import { getPosts } from './blog.ts';
import { FULL_PRICE, LAUNCH_PRICE_ACTIVE, MACS, PRICE, dollars } from './pricing.ts';
import { CONTACT_EMAIL, SITE_URL } from './site.ts';

/** What a key costs today, and the full price while the launch price runs. */
const COST = LAUNCH_PRICE_ACTIVE
  ? `${PRICE} once at the launch price (the full price is ${dollars(FULL_PRICE)})`
  : `${PRICE} once`;

/** The site for a language model, as llmstxt.org describes it: what the app does, the pages and the guides. */
export function llmsTxt(): string {
  const guides = getPosts()
    .map((post) => `- [${post.title}](${SITE_URL}/blog/${post.slug}): ${post.description}`)
    .join('\n');
  return `# Agent Caffeine

> Agent Caffeine is a macOS menu bar app that keeps a Mac awake while AI coding agents work, also with the lid closed, and lets it sleep when they are idle or wait for you. It has a 7-day free trial, then costs ${COST}, and runs on macOS 13 or later (Apple silicon and Intel).

- Detects more than ${agentsMoreThan} coding agents (Claude Code, Codex, Cursor, opencode, Gemini CLI and others). Claude Code, Codex and Cursor report their own state (working, waiting for you, or idle), and Agent Caffeine reads it on the Mac. It also watches the commands an agent started, so a build that is still busy keeps the Mac awake. Other agents are judged by signs of work, such as a running command or a write to the session file.
- An agent that waits for your answer keeps the Mac awake for 5 minutes, then the Mac can sleep. Idle sessions do not keep it awake in the default mode. The times can be changed in Settings.
- Optional better detection: Claude Code, Codex, Cursor, Droid, opencode and Pi can report their state to Agent Caffeine directly. It is off until you switch it on per agent, and switching it off removes it again.
- Three modes: always, while an agent is open, or while an agent is working (the default).
- A closed lid on the power adapter works from the start. On battery it needs a small helper that you allow once in System Settings, and it turns on the \`SleepDisabled\` setting of macOS only while it holds the Mac awake.
- Safety: when the battery is at 20% (adjustable, or off) or the Mac gets too hot, it lets the Mac sleep and says why in a notification. After a battery stop it starts again at 25%, or when the Mac is plugged in. On battery the menu shows the charge and that level on one line.
- The built-in display dims as the lid closes and stays dark while the lid is closed. On a Mac with a lid angle sensor it dims from 45 degrees of lid opening down to closed, and gets bright again the same way when the lid opens.
- A sound when the lid closes: close the lid while Agent Caffeine keeps the Mac awake and the Mac plays one short sound, once. No sound means the Mac goes to sleep. The setting is "Play a sound when you close the lid and your Mac stays awake" in Settings > Battery and lid. It is on by default, and the sound can be Tink (the default), Bottle, Purr or Glass.
- Pause for 30 minutes, 1 hour or until tomorrow. Agent Caffeine starts again by itself.
- Stay reachable for 1, 2 or 4 hours: the Mac stays awake until that time, also when no agent works, so a message from a phone (Claude Code Remote Control, Codex remote) reaches the agent. On battery with the lid closed it needs the helper, and it uses about 1% of battery per hour. A message cannot wake a Mac that sleeps.
- Notifications, each with its own switch: an agent is waiting for your answer (on by default), and an agent finished (off by default).
- A command line tool and an MCP server. \`agent-caffeine hold -- <command>\` keeps the Mac awake while the command runs and ends with its exit code. \`agent-caffeine hold --for 2h\` keeps it awake for a time (1 hour by default, 12 hours at most), and \`agent-caffeine release\` ends that. \`agent-caffeine mcp\` is an MCP server on stdio with the tools \`hold_awake\`, \`release\` and \`status\`. "Set up for agents" in Settings adds a skill to the agents on the Mac, so an agent asks by itself before a long command: asked to render an animation, it runs \`agent-caffeine hold --reason "Blender render" -- blender -b scene.blend -a\`. Each hold has a line in the menu with "Stop". A low battery, heat, a pause and the switch still let the Mac sleep.
- Keyboard shortcuts that work in every app. By default Control+Option+Command+C turns Agent Caffeine on or off, and Control+Option+Command+P pauses it for 1 hour. You can choose other keys.
- The menu bar icon can be hidden. The app keeps the Mac awake the same way without it.
- A 7-day free trial with every feature. It starts the first time the app opens and needs no account, no card and no key. After 7 days the app stops keeping the Mac awake until a license key is entered. The app and its settings stay.
- One license key works on up to ${MACS} Macs and costs ${COST}. It includes 1 year of updates and no subscription. After that year the app keeps working, and a version that comes out later needs a new key. Deactivate a Mac in the app or in your Polar purchases to move the key to another.
- The app updates itself: it checks caffeinagent.com for updates and installs them when you agree.
- No telemetry and no analytics. It reads the process list, the state and session files of Claude Code, Codex and Cursor in \`~/.claude\`, \`~/.codex\` and \`~/.cursor/projects\`, and the battery level and lid angle, all on your own Mac. Its only network calls are the update check to caffeinagent.com and the license key check with Polar, which sends the key and the Mac's model. Nothing about you or your agents leaves the Mac.
- Sold by Mert Duzgun, an individual based in Antalya, Türkiye. Polar (polar.sh) is the merchant of record: it takes the payment, handles tax and sends the invoice. All sales are final, since the full app is free to try for 7 days first. Contact: ${CONTACT_EMAIL}.

## Links

- [Home](${SITE_URL}/): examples of long jobs, the agents it finds, features, a demo, price, questions
- [Compare](${SITE_URL}/compare): Agent Caffeine next to Adrafinil, Hold My Lid, LidRun, Clamshell and Amphetamine, with the price first and a source for each tool
- [Privacy](${SITE_URL}/privacy): what the app, a purchase and the website collect
- [Terms](${SITE_URL}/terms): license, trial, payment, refunds and liability

## Guides

${guides}
`;
}
