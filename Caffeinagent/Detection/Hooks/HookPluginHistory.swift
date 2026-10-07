import Foundation

/// The plugin and extension files that older builds wrote, to the letter.
/// A file on disk that is the same as the text of the version in its first
/// line was not edited by the user, so the app may replace it with the
/// current one: see `HookInstaller.updateOwnFile`. Never change a text
/// here. A new version of a file adds the one before it.
enum HookPluginHistory {
    /// Nil for a version this build does not know.
    static func source(for entry: HookCatalogEntry, version: Int, appPath: String) -> String? {
        let hook = JSONSourceText.literal(HookCatalog.executablePath(appPath: appPath))
        switch (entry.id, version) {
        case ("opencode", 1): return opencode1(hook)
        case ("opencode", 2): return opencode2(hook)
        case (HookCatalog.piID, 1): return pi1(hook)
        default: return nil
        }
    }

    /// The version in the first line of a file of ours.
    static func version(ofSource source: String) -> Int? {
        let first = source.prefix { $0 != "\n" }
        let prefix = "// \(HookCatalog.pluginMarker) v="
        guard first.hasPrefix(prefix) else { return nil }
        return Int(first.dropFirst(prefix.count))
    }

    private static func opencode1(_ hook: String) -> String {
        """
        // agent-caffeine-hook v=1
        // Written by agent caffeine. Turn it off in agent caffeine > Preferences > Agents.
        // It tells agent caffeine when opencode works, waits for you or is done.
        const hook = \(hook);

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

        export const AgentCaffeine = async ({ $ }) => ({
          event: async ({ event }) => {
            try {
              const name = named(event);
              if (!name) return;
              const properties = event?.properties ?? {};
              const session = properties.sessionID ?? properties.info?.id ?? "";
              const input = new Response(JSON.stringify({ session_id: String(session) }));
              await $`${hook} opencode ${name} v=1 < ${input}`.quiet().nothrow();
            } catch {}
          },
        });

        """
    }

    private static func opencode2(_ hook: String) -> String {
        """
        // agent-caffeine-hook v=2
        // Written by agent caffeine. Turn it off in agent caffeine > Preferences > Agents.
        // It tells agent caffeine when opencode works, waits for you or is done.
        const hook = \(hook);

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
          let queue = Promise.resolve();
          let seq = 0;
          let last = "";
          let lastAt = 0;
          return {
            event: async ({ event }) => {
              try {
                const name = named(event);
                if (!name) return;
                const properties = event?.properties ?? {};
                const session = String(properties.sessionID ?? properties.info?.id ?? "");
                const ts = Date.now();
                const key = name + " " + session;
                if (key === last && Math.abs(ts - lastAt) < 1000) return;
                last = key;
                lastAt = ts;
                seq += 1;
                const body = JSON.stringify({ session_id: session, seq, ts });
                queue = queue.then(async () => {
                  try {
                    const input = new Response(body);
                    await $`${hook} opencode ${name} v=2 < ${input}`.quiet().nothrow();
                  } catch {}
                });
              } catch {}
            },
          };
        };

        """
    }

    private static func pi1(_ hook: String) -> String {
        """
        // agent-caffeine-hook v=1
        // Written by agent caffeine. Turn it off in agent caffeine > Preferences > Agents.
        // It tells agent caffeine when Pi works, waits for you or is done.
        import { spawn } from "node:child_process";

        const hook = \(hook);
        const shared = (globalThis[Symbol.for("agent-caffeine.pi.v1")] ??= { queue: Promise.resolve(), seq: 0 });

        const run = (name, body) =>
          new Promise((done) => {
            const timer = setTimeout(done, 5000);
            const end = () => {
              clearTimeout(timer);
              done();
            };
            try {
              timer.unref?.();
              const child = spawn(hook, ["pi", name, "v=1"], { stdio: ["pipe", "ignore", "ignore"], detached: true });
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
              if (key === last && Math.abs(ts - lastAt) < 1000) return;
              last = key;
              lastAt = ts;
              shared.seq += 1;
              const body = JSON.stringify({ session_id: session || "pid-" + process.pid, seq: shared.seq, ts });
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
