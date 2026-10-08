import Foundation

/// How one agent takes hooks: where its config is, what form it has, and
/// what the hooks tell that the passive detection cannot see.
struct HookCatalogEntry: Equatable, Identifiable {
    enum Format: Equatable {
        /// A JSON file with `<key path>.<Event>: [{matcher?, hooks: [{type, command, timeout}]}]`,
        /// the form of Claude Code, Codex and Droid.
        case jsonHookGroups(keyPath: [String])
        /// A JSON file with a top-level `"version": 1` and
        /// `<key path>.<event>: [{command, timeout}]`, the form of Cursor.
        case jsonFlatHooks(keyPath: [String])
        /// A JavaScript plugin or extension file that is all ours.
        case pluginFile

        /// Nil for a file that is no JSON config.
        var jsonLayout: (keyPath: [String], flat: Bool)? {
            switch self {
            case .jsonHookGroups(let keyPath): return (keyPath, false)
            case .jsonFlatHooks(let keyPath): return (keyPath, true)
            case .pluginFile: return nil
            }
        }
    }

    /// The hook agent id, the first argument of the hook command.
    let id: String
    let displayName: String
    /// Relative to the home folder.
    let configPath: String
    let format: Format
    /// The states the hooks add to what Agent Caffeine sees without them.
    let adds: [ReportedState]
    /// One line for Preferences: what turning it on gives.
    let benefit: String
    /// What the user has to do in the agent after turning it on.
    let afterInstall: String?
    /// What the config path, the format and the event names were checked against.
    let confirmedBy: String

    var rules: [HookEvents.Rule] { HookEvents.rules[id] ?? [] }
    var definitionIDs: Set<String> { HookEvents.definitionIDs[id] ?? [] }
    var events: [String] { rules.map(\.event) }
}

enum HookCatalog {
    /// Raised when the command or the set of events changes, so entries of
    /// an older build read as outdated.
    static let version = 1
    /// The same for the opencode plugin file, which is all ours. It has a
    /// number of its own, so a new plugin does not make the entries of the
    /// other agents read as outdated. 2: the events go to the hook command
    /// one after the other, with a stamp of their order. 3: a hook command
    /// that does not end is left after `timeoutSeconds`, and the stamp
    /// names the plugin instance that counts.
    static let pluginVersion = 3
    /// The same for the Pi extension file. 2: a hook command that does
    /// not end is killed after `timeoutSeconds`, and the stamp names the
    /// Pi process that counts.
    static let piExtensionVersion = 2
    /// Two events of one name for one session this close together are one:
    /// opencode sends `session.status` idle and `session.idle` in the same
    /// millisecond. A later busy of the same turn is passed on: it starts
    /// `VerdictRules.hookWorkingLimit` again.
    static let pluginRepeatMilliseconds = 1000
    /// Every entry we write holds this, and nothing else in a config does.
    static let marker = "/Contents/MacOS/CaffeinagentHook"
    /// The hook command points here and nowhere else, so it stays valid
    /// when the app updates and when a copy runs from another folder.
    static let stableAppPath = "/Applications/agent caffeine.app"
    static let timeoutSeconds = 5
    static let pluginFileName = "agent-caffeine.js"

    static let entries: [HookCatalogEntry] = [
        HookCatalogEntry(
            id: "claude", displayName: "Claude Code", configPath: ".claude/settings.json",
            format: .jsonHookGroups(keyPath: ["hooks"]),
            adds: [.waitingForUser],
            benefit: "Tells Agent Caffeine when Claude Code is waiting for your permission.",
            afterInstall: nil,
            confirmedBy: "code.claude.com/docs/en/hooks, and the file on the test Mac"
        ),
        HookCatalogEntry(
            id: "codex", displayName: "Codex", configPath: ".codex/hooks.json",
            format: .jsonHookGroups(keyPath: ["hooks"]),
            adds: [.waitingForUser],
            benefit: "Tells Agent Caffeine when Codex is waiting for your permission.",
            afterInstall: "One more step for Codex: type /hooks in Codex and approve Agent Caffeine.",
            confirmedBy: "learn.chatgpt.com/docs/hooks, the Codex 0.159 binary, and the file on the test Mac"
        ),
        HookCatalogEntry(
            id: "droid", displayName: "Droid", configPath: ".factory/settings.json",
            format: .jsonHookGroups(keyPath: ["hooks"]),
            adds: [.working, .waitingForUser, .idle],
            benefit: "Tells Agent Caffeine when Droid is working, waiting for you or done.",
            afterInstall: nil,
            confirmedBy: "docs.factory.com/cli/configuration/hooks-guide, and the file on the test Mac"
        ),
        HookCatalogEntry(
            id: "opencode", displayName: "opencode", configPath: ".config/opencode/plugins/\(pluginFileName)",
            format: .pluginFile,
            adds: [.working, .waitingForUser, .idle],
            benefit: "Tells Agent Caffeine when opencode is working, waiting for you or done.",
            afterInstall: "opencode loads the plugin the next time it starts.",
            confirmedBy: "opencode.ai/docs/plugins for the folder, the plugin form and the event names. The event payload and the call of `event` without a wait are from the opencode 1.18.16 binary. A turn was measured live."
        ),
        HookCatalogEntry(
            id: piID, displayName: "Pi", configPath: ".pi/agent/extensions/\(pluginFileName)",
            format: .pluginFile,
            adds: [.working, .waitingForUser, .idle],
            benefit: "Lets Agent Caffeine see at once when Pi starts and stops working",
            afterInstall: "Pi loads the extension the next time it starts, or when you type /reload in Pi.",
            confirmedBy: "Pi 1.0.4 on the test Mac: docs/extensions.md and docs/configuration.md for the folder and the form, dist/core/extensions/types.d.ts for the event names, dist/core/extensions/runner.js and dist/core/agent-session.js for the wait on each handler and for agent_settled after every run. The extension was loaded by Pi and its session events were recorded. A turn with a model was not run live."
        ),
        HookCatalogEntry(
            id: "cursor", displayName: "Cursor", configPath: ".cursor/hooks.json",
            format: .jsonFlatHooks(keyPath: ["hooks"]),
            adds: [],
            benefit: "Lets Agent Caffeine see at once when Cursor starts and stops working",
            afterInstall: nil,
            confirmedBy: "cursor.com/docs/hooks for the form and the events, and the file on the test Mac. Our entries were not run live."
        ),
    ]

    /// Known hook systems that are left out, and why.
    static let notConfirmed: [(agent: String, reason: String)] = [
        ("Cursor CLI", "It is not known which hooks.json events fire in cursor-agent, or what an empty answer does to beforeSubmitPrompt."),
        ("Gemini CLI", "The settings.json hook format is known from source only, and no Gemini config exists on the test Mac."),
        ("Grok, Amp, Antigravity, Copilot", "Known from another project's catalogue only."),
    ]

    static func entry(id: String) -> HookCatalogEntry? {
        entries.first { $0.id == id }
    }

    static func entry(forDefinition id: String) -> HookCatalogEntry? {
        entries.first { $0.definitionIDs.contains(id) }
    }

    static func executablePath(appPath: String = stableAppPath) -> String {
        appPath + marker
    }

    /// For `sh`: the path in single quotes, so a space in it is safe.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The command of one event. It does nothing when the app is gone, and
    /// it never fails: a hook that fails shows an error in the agent.
    static func command(agent: String, event: String, appPath: String = stableAppPath) -> String {
        let executable = shellQuoted(executablePath(appPath: appPath))
        return "[ -x \(executable) ] && \(executable) \(agent) \(event) v=\(version) || true"
    }

    static func version(ofCommand command: String) -> Int? {
        guard let range = command.range(of: #" v=(\d+)"#, options: .regularExpression) else { return nil }
        return Int(command[range].dropFirst(3))
    }

    /// The opencode plugin. It hands each event to the hook command with
    /// the session id, the number of the event and its time, and nothing
    /// else. opencode calls `event` for each bus event and does not wait
    /// for the answer, and it sends the busy of the last step and the idle
    /// of the turn a millisecond apart. So the plugin keeps a queue: a hook
    /// command starts when the one before it has ended, or after
    /// `timeoutSeconds`: one command that hangs must not hold back every
    /// later event of the process. The shell of Bun (`$`) has no way to
    /// stop a command (checked with Bun 1.3.14), so that one is left
    /// behind. `event` never waits for the queue.
    static func pluginSource(appPath: String = stableAppPath) -> String {
        """
        // \(pluginMarker) v=\(pluginVersion)
        // Written by agent caffeine. Turn it off in agent caffeine > Preferences > Agents.
        // It tells agent caffeine when opencode works, waits for you or is done.
        const hook = \(JSONSourceText.literal(executablePath(appPath: appPath)));

        const named = (event) => {
          const properties = event?.properties ?? {};
          switch (event?.type) {
            case "session.status": {
              const status = typeof properties.status === "string" ? properties.status : properties.status?.type;
              if (status === "busy" || status === "retry") return "session.busy";
              return status === "idle" ? "session.idle" : null;
            }
            case "session.idle":
            case "session.deleted":
            case "permission.asked":
            case "permission.replied":
              return event.type;
            default:
              return null;
          }
        };

        export const AgentCaffeine = async ({ $ }) => {
          const inst = Math.random().toString(36).slice(2) + Date.now().toString(36);
          let queue = Promise.resolve();
          let seq = 0;
          let last = "";
          let lastAt = 0;
          const run = (name, body) =>
            new Promise((done) => {
              const timer = setTimeout(done, \(timeoutSeconds * 1000));
              const end = () => {
                clearTimeout(timer);
                done();
              };
              try {
                timer.unref?.();
                const input = new Response(body);
                $`${hook} opencode ${name} v=\(pluginVersion) < ${input}`.quiet().nothrow().then(end, end);
              } catch {
                end();
              }
            });
          return {
            event: async ({ event }) => {
              try {
                const name = named(event);
                if (!name) return;
                const properties = event?.properties ?? {};
                const session = String(properties.sessionID ?? properties.info?.id ?? "");
                const ts = Date.now();
                const key = name + " " + session;
                if (key === last && Math.abs(ts - lastAt) < \(pluginRepeatMilliseconds)) return;
                last = key;
                lastAt = ts;
                seq += 1;
                const body = JSON.stringify({ session_id: session, seq, ts, inst });
                queue = queue.then(() => run(name, body));
              } catch {}
            },
          };
        };

        """
    }

    static let pluginMarker = "agent-caffeine-hook"
    static let piID = "pi"

    /// The file of an entry of the form `.pluginFile`.
    static func pluginSource(for entry: HookCatalogEntry, appPath: String = stableAppPath) -> String {
        entry.id == piID ? piExtensionSource(appPath: appPath) : pluginSource(appPath: appPath)
    }

    static func pluginVersion(for entry: HookCatalogEntry) -> Int {
        entry.id == piID ? piExtensionVersion : pluginVersion
    }

    /// The Pi extension. It hands each event to the hook command with the
    /// session id, the number of the event and its time, and nothing else.
    /// Pi waits for each handler, so a handler only puts the event in the
    /// queue and returns: a hook command starts when the one before it has
    /// ended, and Pi never waits for one. A handler never throws. Only
    /// events that tell and change nothing are taken: a handler of
    /// `tool_call` that fails blocks the tool. The queue and the number are
    /// kept for the process, because `/reload` and a new session load the
    /// extension anew. A hook command that does not end within
    /// `timeoutSeconds` is killed, and the queue goes on.
    ///
    /// Pi has no permission step of its own. Another extension can ask the
    /// user (`ui_prompt_start`), and that is a wait only during a run. A
    /// compaction that the user starts is work with no run around it.
    static func piExtensionSource(appPath: String = stableAppPath) -> String {
        """
        // \(pluginMarker) v=\(piExtensionVersion)
        // Written by agent caffeine. Turn it off in agent caffeine > Preferences > Agents.
        // It tells agent caffeine when Pi works, waits for you or is done.
        import { spawn } from "node:child_process";

        const hook = \(JSONSourceText.literal(executablePath(appPath: appPath)));
        const shared = (globalThis[Symbol.for("agent-caffeine.pi.v\(piExtensionVersion)")] ??= {
          queue: Promise.resolve(),
          seq: 0,
          inst: Math.random().toString(36).slice(2) + Date.now().toString(36),
        });

        const run = (name, body) =>
          new Promise((done) => {
            let child;
            const timer = setTimeout(() => {
              try {
                child?.kill("SIGKILL");
              } catch {}
              done();
            }, \(timeoutSeconds * 1000));
            const end = () => {
              clearTimeout(timer);
              done();
            };
            try {
              timer.unref?.();
              child = spawn(hook, ["\(piID)", name, "v=\(piExtensionVersion)"], { stdio: ["pipe", "ignore", "ignore"], detached: true });
              child.on("error", end);
              child.on("close", end);
              child.stdin.on("error", () => {});
              child.stdin.end(body);
              child.unref();
            } catch {
              end();
            }
          });

        export default function (pi) {
          let session = "";
          let last = "";
          let lastAt = 0;
          let running = false;
          let asked = false;

          const send = (name, ctx) => {
            try {
              try {
                session = String(ctx?.sessionManager?.getSessionId?.() ?? "") || session;
              } catch {}
              const ts = Date.now();
              const key = name + " " + session;
              if (key === last && Math.abs(ts - lastAt) < \(pluginRepeatMilliseconds)) return;
              last = key;
              lastAt = ts;
              shared.seq += 1;
              const body = JSON.stringify({ session_id: session || "pid-" + process.pid, seq: shared.seq, ts, inst: shared.inst });
              shared.queue = shared.queue.then(() => run(name, body));
            } catch {}
          };
          const on = (name, handler) => {
            try {
              pi.on(name, (_event, ctx) => {
                try {
                  handler(ctx);
                } catch {}
              });
            } catch {}
          };
          const rests = (name) =>
            on(name, (ctx) => {
              running = false;
              asked = false;
              send(name, ctx);
            });

          rests("session_start");
          for (const name of ["agent_start", "turn_start", "tool_execution_start", "tool_execution_end"]) {
            on(name, (ctx) => {
              running = true;
              if (!asked) send(name, ctx);
            });
          }
          on("ui_prompt_start", (ctx) => {
            if (!running) return;
            asked = true;
            send("ui_prompt_start", ctx);
          });
          on("ui_prompt_end", (ctx) => {
            if (!asked) return;
            asked = false;
            send("ui_prompt_end", ctx);
          });
          on("session_before_compact", (ctx) => {
            if (!asked) send("session_before_compact", ctx);
          });
          for (const name of ["session_compact", "session_compact_failed"]) {
            on(name, (ctx) => {
              if (!running) send(name, ctx);
            });
          }
          rests("agent_settled");
          rests("session_shutdown");
        }

        """
    }
}
