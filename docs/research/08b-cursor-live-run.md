# Cursor editor agent: live run on the owner's Mac (2026-10-07, Cursor 3.x, macOS 26)

Read-only sampler, 2 s period: raw data in `cursor-run/` (ps.tsv, children.tsv, writes.tsv, marks.tsv).

Timeline (owner's marks): 10:15:34 idle baseline ended; about 10:15:55 first prompt sent; 10:16:16 agent streaming;
10:17:38 agent runs `sleep 60` (no approval asked: auto-run on); 10:18:38 command ends; 10:18:41 agent done.

## Proven
1. Transcript with turn markers. Cursor writes one JSONL per agent session at
   `~/.cursor/projects/<project-slug>/agent-transcripts/<session-uuid>/<session-uuid>.jsonl`
   (here project slug `empty-window`). Line shapes (keys only):
   - `{"role":"user","message":{"content":[{"type":…,"text":…}]}}`
   - `{"role":"assistant","message":{"content":[{"type":…,"text":…}]}}` and tool calls
     `{"role":"assistant","message":{"content":[{"type":…,"name":…,"input":{…}}]}}`
   - `{"type":"turn_ended","status":"success"}` at the end of each turn (3 turns seen, 3 markers).
   So: a `user` line with no later `turn_ended` = a turn in progress. Same idea as Claude Code and Codex.
   Write times of the file: 10:15:55 (user line, size 533), 10:17:11 (8995), 10:17:26 (9183), 10:18:34 (9603, turn end).
   It is NOT written continuously: nothing between 10:17:26 and 10:18:34 while `sleep 60` ran, so write recency alone is
   a bad signal; the missing `turn_ended` marker is the signal.
2. Agent-run commands are child processes of the extension host:
   `Cursor Helper (Plugin): extension-host Agents Window [1-1]` (pid 53880) -> `/bin/zsh -c …` -> `sleep 60`.
   Visible in the process table for the whole run.
3. CPU is useless: the extension host stayed at 0.6 to 3.7 percent through idle, streaming and the command.
4. Noise at idle: `AgentStores/cursor_agent_stores/*/.sync/sync.lock` and `index.sqlite-wal` are written every few
   seconds at all times (105 writes in 4 minutes): never use AgentStores writes as an activity signal.
   `User/globalStorage/state.vscdb-wal` also moves at idle.
5. Logs that move with agent work: `logs/<stamp>/window1_wb0/exthost/anysphere.cursor-agent-exec/Cursor Agent Exec.*.log`
   (16 writes, only between 10:16:32 and 10:18:00), `…/output_*/cursor.hooks.workspaceId-*.log` (hook runs: the owner
   has hooks from other tools in `~/.cursor/hooks.json`, and Cursor ran them: hooks work in the editor's agent),
   `…/exthost/anysphere.cursor-always-local/Cursor Structured Logs.*.log` (busy always).
6. Cursor held no power assertion at any time.
7. Process titles are rewritten (`Cursor Helper (Plugin): extension-host Agents Window [1-1]`), so match on the
   executable path (`/Applications/Cursor.app/Contents/Frameworks/Cursor Helper (Plugin).app/Contents/MacOS/Cursor Helper (Plugin)`)
   plus the title text, or on the main binary `/Applications/Cursor.app/Contents/MacOS/Cursor` for presence.

## Not seen yet
- A command approval wait (auto-run is on for the owner): unknown how it shows in the transcript, logs or hooks.
- `turn_ended` statuses other than `success` (aborted, error).
- Several agent sessions at once, a project with a real folder (slug format), background/cloud agents, worktree agents.
- Whether the transcript path is the same for the classic editor window and the Agents Window.

## Approval wait, measured later the same day (Allowlist mode)
Marks in `cursor-run/marks.tsv`.
- 10:25:59 prompt; the "Electron" assertion is taken. 10:26:02 the transcript gets a `user` and an `assistant` line.
- 10:26:12 the assertion is released, 10 s after the last transcript write. The approval prompt is shown.
  From 10:26:12 to 10:38:54 (12 minutes): the turn is open (no `turn_ended`), no assertion, no agent child command, no transcript write.
- 10:38:54 the owner pressed Run: the assertion is held 10:38:54 to 10:39:00.
  10:39:09 the transcript gets an `assistant` line and `{"type":"turn_ended","status":"success"}`, 9 s after the assertion dropped.

So "open turn, no assertion, no agent command" is the approval wait. The end of a turn looks the same for 9 s, so the rule
waits 15 s before it says "waiting" (`CursorApprovalRule.settle`).
Also seen: an agent CLI in Cursor's integrated terminal, and what it runs, are descendants of Cursor. Only a shell directly
below an extension host counts as a command of Cursor's agent.
