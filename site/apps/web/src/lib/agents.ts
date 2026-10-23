import type { AgentIconName } from '../components/agent-icons.tsx';

type Agent = { icon?: AgentIconName; name: string };

/** Every agent Agent Caffeine knows, those with a mark first. */
const agents: ReadonlyArray<Agent> = [
  { icon: 'claudecode', name: 'Claude Code' },
  { icon: 'codex', name: 'Codex' },
  { icon: 'opencode', name: 'opencode' },
  { icon: 'pi', name: 'Pi' },
  // One entry for the editor and for its command line agent (`cursor-agent`): the app finds both.
  { icon: 'cursor', name: 'Cursor' },
  { icon: 'antigravity', name: 'Antigravity' },
  { icon: 'grok', name: 'Grok Build' },
  { icon: 'geminicli', name: 'Gemini CLI' },
  { icon: 'amp', name: 'Amp' },
  { icon: 'goose', name: 'Goose' },
  { icon: 'cline', name: 'Cline' },
  { icon: 'windsurf', name: 'Windsurf' },
  { icon: 'openhands', name: 'OpenHands' },
  { icon: 'junie', name: 'Junie' },
  { icon: 'zencoder', name: 'Zencoder' },
  { icon: 'trae', name: 'Trae' },
  { icon: 'qwen', name: 'Qwen Code' },
  { icon: 'qoder', name: 'Qoder' },
  { icon: 'codebuddy', name: 'CodeBuddy' },
  { icon: 'mistral', name: 'Mistral Vibe' },
  { icon: 'devin', name: 'Devin' },
  { icon: 'kilocode', name: 'Kilo Code' },
  { icon: 'kiro', name: 'Kiro CLI' },
  { icon: 'hermesagent', name: 'Hermes Agent' },
  { icon: 'openclaw', name: 'OpenClaw' },
  { icon: 'commandcode', name: 'Command Code' },
  { icon: 'githubcopilot', name: 'GitHub Copilot' },
  { name: 'Aider' },
  { name: 'AiderDesk' },
  { name: 'Crush' },
  { name: 'Tabnine CLI' },
  { name: 'Continue' },
  { name: 'Droid' },
  { name: 'Augment' },
  { name: 'Firebender' },
  { name: 'ForgeCode' },
  { name: 'iFlow CLI' },
  { name: 'Pochi' },
  { name: 'Rovo Dev' },
  { name: 'Deep Agents' },
  { name: 'Neovate' },
  { name: 'MCPJam' },
  { name: 'CodeStudio' },
  { name: 'CodeMaker' },
  { name: 'CodeArts Agent' },
  { name: 'Dexto' },
];

/** The largest round ten below the number of agents, for copy that says "more than". */
export const agentsMoreThan = Math.floor((agents.length - 1) / 10) * 10;

/** The agents with a mark, to show where only a mark will do. */
export const markedAgents = agents.filter(
  (agent): agent is Required<Agent> => agent.icon !== undefined,
);
