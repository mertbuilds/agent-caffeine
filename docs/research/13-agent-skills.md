# 13 - Agent skills: which agents read a `SKILL.md` from a folder of the user, and where

Date: 2026-10-09. For "Set up for agents": one click that writes the skill of the command line tool
(`skills/agent-caffeine/SKILL.md`) where the agents on the Mac read it. Nothing was written below the home folder for
this research, and no agent was started. On the Mac of the owner only the existence of folders was looked at, and the
docs that two agents ship with their install were read.

Marks: [DOC] the official docs on the web, read on the date above. [PKG] the docs in the installed package (path
given). [MAC] seen on this Mac. [UNKNOWN] not confirmed.

## 0. Result

A skill is a folder `<name>/SKILL.md` with YAML frontmatter `name` and `description`. Every agent below loads it from
at least one folder of the user. Two folders reach all of them: `~/.claude/skills` and `~/.agents/skills`.

| Agent | Folder that shows it is set up | Folders of the user it reads | Source |
|---|---|---|---|
| Claude Code | `~/.claude` | `~/.claude/skills` | [DOC] https://code.claude.com/docs/en/skills |
| Codex | `~/.codex` | `~/.agents/skills` | [DOC] https://learn.chatgpt.com/docs/build-skills (from developers.openai.com/codex/skills) |
| opencode | `~/.config/opencode` | `~/.config/opencode/skills`, `~/.claude/skills`, `~/.agents/skills` | [DOC] https://opencode.ai/docs/skills/ |
| Cursor | `~/.cursor` | `~/.cursor/skills`, `~/.agents/skills`, and `~/.claude/skills`, `~/.codex/skills` for compatibility | [DOC] https://cursor.com/docs/context/skills |
| Gemini CLI | `~/.gemini` | `~/.gemini/skills`, `~/.agents/skills` (alias, wins over the first) | [DOC] https://geminicli.com/docs/cli/skills/ |
| Pi | `~/.pi/agent` | `~/.agents/skills` | [PKG] `docs/skills.md` of `@earendil-works/pi-coding-agent` 1.0.4 |
| Droid | `~/.factory` | `~/.factory/skills`, `~/.agents/skills` | [DOC] https://docs.factory.com/cli/configuration/skills |
| Grok Build | `~/.grok` | `~/.grok/skills`, `~/.agents/skills`, and `~/.claude/skills`, `~/.cursor/skills` unless turned off | [PKG] `~/.grok/docs/user-guide/08-skills.md` |
| Amp | `~/.config/amp` | `~/.config/agents/skills`, `~/.agents/skills`, `~/.config/amp/skills`, `~/.claude/skills` | [DOC] https://ampcode.com/docs/customize/skills |
| goose | `~/.config/goose` | `~/.agents/skills`, and `~/.claude/skills` for older setups | [DOC] https://goose-docs.ai/docs/guides/context-engineering/using-skills/ |
| OpenClaw | `~/.openclaw` | `~/.agents/skills` (with the state folder at its default place) | [DOC] https://docs.openclaw.ai/tools/skills |

Left out:

- Hermes Agent. [DOC] https://hermes-agent.nousresearch.com/docs/user-guide/features/skills names `~/.hermes/skills`
  as "the primary directory and source of truth", which the agent itself changes: it can patch and delete any skill
  there. The page for skill authors names no place where a user puts a skill by hand. `~/.agents/skills` is read only
  when the user adds it to `skills.external_dirs` in `~/.hermes/config.yaml`, a file we do not touch. [UNKNOWN] whether
  a flat `~/.hermes/skills/<name>/SKILL.md` is taken as it is.
- `~/.codex/skills`. Older Codex builds read it, and the folder is on this Mac [MAC]. The docs of today name only
  `$HOME/.agents/skills` for the user, so the old folder is not written to.
- A folder of Pi's own. The docs say "Place the skill in your user or project skills directory" and give no path for
  it. They name `~/.agents/skills/`, so that one is used.
- `~/.openclaw/skills`. The docs call it "Managed / local skills" of the state folder. `~/.agents/skills` is the folder
  for "Personal agent skills", so that one is used.
- `~/.config/agents/skills` (Amp, and older goose docs). Nothing needs it: both also read `~/.agents/skills`.

## 1. What the docs say, agent by agent

- Claude Code [DOC]: personal skills are `~/.claude/skills/<skill-name>/SKILL.md`. No field is required, `description`
  is recommended, and `description` with `when_to_use` is cut at 1,536 characters in the list. A change of a skill in
  `~/.claude/skills` is picked up in a running session. A top-level skills folder that did not exist when the session
  started needs `/reload-skills` or a new session.
- Codex [DOC]: user skills are in `$HOME/.agents/skills`, admin skills in `/etc/codex/skills`. "Codex supports
  symlinked skill folders and follows the symlink target". `name` and `description` are required. "Codex detects skill
  changes automatically. If an update doesn't appear, restart Codex."
- opencode [DOC]: global paths `~/.config/opencode/skills/*/SKILL.md`, `~/.claude/skills/*/SKILL.md`,
  `~/.agents/skills/*/SKILL.md`. `name` is 1 to 64 characters, `^[a-z0-9]+(-[a-z0-9]+)*$`, and has to be the name of
  the folder. `description` is 1 to 1024 characters.
- Cursor [DOC]: `~/.agents/skills/` and `~/.cursor/skills/` for the user, and `~/.claude/skills/`, `~/.codex/skills/`
  as compatibility paths. `name` (lowercase letters, numbers and hyphens, the name of the folder) and `description`
  are required.
- Gemini CLI [DOC]: user skills are in `~/.gemini/skills/` "or the `~/.agents/skills/` alias", and within one tier the
  alias wins.
- Pi [PKG]: "Pi also supports the Agent Skills locations `~/.agents/skills/` and `.agents/skills/`." Names of at most
  64 characters, descriptions of at most 1024. "Name collisions keep the first discovered skill and produce a
  warning." `/reload` after a change in a running session.
- Droid [DOC]: `~/.factory/skills/<skill-name>/SKILL.md`, and `~/.agents/skills/**/SKILL.md` as a compatibility path.
  `name` and `description` are required.
- Grok Build [PKG]: `~/.grok/skills/` for the user, `.agents/skills/` at each tier next to `.grok/`, and
  `~/.claude/skills/` and `~/.cursor/skills/` by default. The last two can be turned off under `[compat.claude]` and
  `[compat.cursor]` in `~/.grok/config.toml`. Skills of one name are deduplicated.
- Amp [DOC]: in this order `~/.config/agents/skills/`, `~/.agents/skills/`, `~/.config/amp/skills/`, the project
  folders, `~/.claude/skills/`. `amp.skills.disableClaudeCodeSkills` and `amp.skills.disableGlobalAgentsSkills` turn
  two of them off.
- goose [DOC]: `~/.agents/skills/` for global skills, and for older setups `~/.claude/skills/` and others.
- OpenClaw [DOC]: `~/.agents/skills` for "Personal agent skills (default state only)": only while
  `OPENCLAW_STATE_DIR` is not set to another folder. A changed `SKILL.md` is picked up by a watcher or with the next
  session.

## 2. What follows for the installer

- The frontmatter has `name: agent-caffeine` and `description` and nothing else, the name is the name of the folder,
  and the description is below 1024 characters. That is what the strictest of them take (opencode, Cursor, Pi).
- One copy per agent would show the skill two or three times to opencode, Cursor, Gemini CLI, Grok Build and Amp,
  and Pi prints a warning for a name it finds twice. So the skill goes to as few folders as reach every agent on the
  Mac. The agents with one folder come first (Claude Code: `~/.claude/skills`. Codex, Pi, OpenClaw:
  `~/.agents/skills`). An agent that reads a folder the skill is then in gets nothing more. An agent that reads none
  of them gets its own folder, the first of its list.
- `~/.agents/skills` is made when it is not there, because for Codex it is the only folder. The app records the
  folders it made and removes them again when they are empty.
- An agent that reads the skill from the folder of another agent does not see it when its owner turned that reading
  off (Grok Build, Amp). The app cannot see that setting without reading the agent's config, which it does not do.
  [UNKNOWN] how often that is.
- [MAC] On this Mac the folders `~/.claude`, `~/.codex`, `~/.config/opencode`, `~/.cursor`, `~/.gemini`, `~/.pi/agent`,
  `~/.factory`, `~/.config/goose`, `~/.grok`, `~/.hermes`, `~/.openclaw`, `~/.agents/skills` and `~/.local/bin` are
  there, and `~/.config/amp` is not. So one click writes `~/.claude/skills/agent-caffeine/SKILL.md` and
  `~/.agents/skills/agent-caffeine/SKILL.md`, and the link.
- A common setup has one real skills folder and links to it from the folders of the agents (for example
  `~/.claude/skills` as a link to `~/.agents/skills`). The app does not write through a link that leads out of an
  agent's folder. It reads through it, so the skill in the real folder counts for that agent.

## 3. The PATH

- A link in `~/.local/bin` is found only when that folder is on the PATH. It is no default of macOS.
- The app asks a login shell that is not interactive for its PATH (`$SHELL -l -c`, no input, 5 seconds at most). zsh
  then reads `.zshenv`, `.zprofile` and `.zlogin`, and not `.zshrc`, where most people set their PATH. So the app also
  reads the shell's own startup files and takes the folder as on the PATH when one of them names `.local/bin`.
- It says "not on your PATH" only for zsh and bash, when the login shell gave a PATH without the folder and no startup
  file names it. In every other case it says nothing. A PATH that is set in a file that `.zshrc` sources from elsewhere
  is not seen, so the line says "does not seem to be".
- The skill tells the agent to use the full path of the tool when the command is not found, so the skill works in
  both cases.
