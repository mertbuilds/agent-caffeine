import type { AgentIconName } from "@/components/agent-icons";

type Agent = { name: string; icon?: AgentIconName };

/** Every agent Agent Caffeine knows, those with a mark first. */
export const agents: readonly Agent[] = [
  { name: "Claude Code", icon: "claudecode" },
  { name: "Codex", icon: "codex" },
  { name: "opencode", icon: "opencode" },
  { name: "Pi", icon: "pi" },
  // One entry for the editor and for its command line agent (`cursor-agent`): the app finds both.
  { name: "Cursor", icon: "cursor" },
  { name: "Antigravity", icon: "antigravity" },
  { name: "Grok Build", icon: "grok" },
  { name: "Gemini CLI", icon: "geminicli" },
  { name: "Amp", icon: "amp" },
  { name: "Goose", icon: "goose" },
  { name: "Cline", icon: "cline" },
  { name: "Windsurf", icon: "windsurf" },
  { name: "OpenHands", icon: "openhands" },
  { name: "Junie", icon: "junie" },
  { name: "Zencoder", icon: "zencoder" },
  { name: "Trae", icon: "trae" },
  { name: "Qwen Code", icon: "qwen" },
  { name: "Qoder", icon: "qoder" },
  { name: "CodeBuddy", icon: "codebuddy" },
  { name: "Mistral Vibe", icon: "mistral" },
  { name: "Devin", icon: "devin" },
  { name: "Kilo Code", icon: "kilocode" },
  { name: "Kiro CLI", icon: "kiro" },
  { name: "Hermes Agent", icon: "hermesagent" },
  { name: "OpenClaw", icon: "openclaw" },
  { name: "Command Code", icon: "commandcode" },
  { name: "GitHub Copilot", icon: "githubcopilot" },
  { name: "Aider" },
  { name: "AiderDesk" },
  { name: "Crush" },
  { name: "Tabnine CLI" },
  { name: "Continue" },
  { name: "Droid" },
  { name: "Augment" },
  { name: "Firebender" },
  { name: "ForgeCode" },
  { name: "iFlow CLI" },
  { name: "Pochi" },
  { name: "Rovo Dev" },
  { name: "Deep Agents" },
  { name: "Neovate" },
  { name: "MCPJam" },
  { name: "CodeStudio" },
  { name: "CodeMaker" },
  { name: "CodeArts Agent" },
  { name: "Dexto" },
];

/** The largest round ten below the number of agents, for copy that says "more than". */
export const agentsMoreThan = Math.floor((agents.length - 1) / 10) * 10;

/** The agents with a mark, to show where only a mark will do. */
export const markedAgents = agents.filter(
  (agent): agent is Required<Agent> => agent.icon !== undefined,
);
