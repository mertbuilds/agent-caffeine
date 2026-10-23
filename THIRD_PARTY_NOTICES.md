# Third-party notices

Agent Caffeine for Mac is Copyright (C) 2026 Mert Düzgün. All rights
reserved. See `LICENSE` beside this file.

The app carries the components below, each under its own license. The full
license texts are in `Resources/Licenses/` beside this file, and in
`Contents/Resources/Licenses/` inside the app, next to a copy of this file.

## Components

| Component | Version | License | In the app as | Source |
| --- | --- | --- | --- | --- |
| Sparkle | 2.10.0 | MIT | `Contents/Frameworks/Sparkle.framework` | <https://github.com/sparkle-project/Sparkle/tree/2.10.0> |
| lobe-icons | not pinned | MIT | Most of the agent marks in `Caffeinagent/UI/Panel/Model/AgentLogoData.swift` | <https://github.com/lobehub/lobe-icons> |

Sparkle comes in as a Swift package: `project.yml` asks for exactly 2.10.0.

License texts, by file name in `Resources/Licenses/`:

- `Sparkle.txt`: the MIT license of Sparkle with its copyright lines, followed
  by the licenses of the code Sparkle itself includes (bsdiff, sais-lite,
  ed25519 and SUSignatureVerifier).
- `lobe-icons.txt`: the MIT license of lobe-icons.
- `MIT-agent-files.txt`: the MIT license for the files that Agent Caffeine
  writes into the folders of your agents (see below).

## The agent marks

The menu shows a mark beside each agent. The drawings are path data on a 24 by
24 canvas in `AgentLogoData.swift`.

- Most of them are drawings from lobe-icons, under its MIT license.
- Pi (`pi`) is the mark from the project's own site, https://pi.dev/logo-auto.svg,
  taken on 2026-10-08.
- opencode (`opencode`) follows the mark of https://opencode.ai/favicon.svg,
  taken on 2026-10-08.
- OpenClaw (`openclaw`) and Hermes Agent (`hermesagent`) are from lobe-icons
  (`openclaw-color.svg` and `hermesagent.svg`).
- Command Code (`commandcode`) is the mark that its own project shows. The file
  the drawing was taken from is not recorded.

The agent names and logos are trademarks of their owners and are used only to
identify those products. Agent Caffeine is not affiliated with or endorsed by
any of them. See `TRADEMARKS.md`.

## The files Agent Caffeine writes into the folders of your agents

Agent Caffeine writes small files into the configuration of your agents: the
hook lines it adds to the settings files of the agents, the opencode plugin,
the Pi extension and the skill `agent-caffeine` (`SKILL.md`). You may also use
these files under the MIT license in `Resources/Licenses/MIT-agent-files.txt`,
Copyright (c) 2026 Mert Duzgun. So they put no term of the license of the
app on your own agent configuration, and you can copy the skill into any
skill folder.

## Facts and ideas from other projects

- The table of the agents and their skill folders follows the list of
  [vercel-labs/skills](https://github.com/vercel-labs/skills) (MIT). It holds
  names and paths, and no code of that project.
- "Wake for jobs" learned from [goguma](https://github.com/junnam586/goguma)
  (MIT): one wake time for the nearest job, read from crontab, launchd and the
  jobs of Hermes Agent. No code of it is in this repository.
- `docs/research/01-oss-detection.md` names the open source projects whose way
  of finding an agent was read, each at a named commit.
