"""One sample of the watches: what the Mac and the app say at one moment."""
import json
import os
import plistlib

from . import config, parse


def app_state(env, pids):
    """The state the app wrote for tests. None when the app does not
    run, the file is not there, it is older than the app could leave it,
    or it is of a process that is gone."""
    data = env.read(config.state_file()) if pids else None
    if not data:
        return None
    try:
        state = json.loads(data)
    except ValueError:
        return None
    if not isinstance(state, dict) or env.now() - state.get("at", 0) > config.STATE_MAX_AGE:
        return None
    if (state.get("app") or {}).get("pid") not in pids:
        return None
    return state


def status(env, pid):
    """`awake` and `stopped` of the .status file. The line is left out:
    it holds the name of an agent."""
    data = env.read(config.status_file()) if pid is not None else None
    if not data:
        return None
    try:
        found = json.loads(data)
    except ValueError:
        return None
    return {"awake": bool(found.get("awake")), "stopped": bool(found.get("stopped"))}


def probe(env, spec, run_dir):
    """A look at one of our own files. The content is never kept."""
    path = spec["path"].replace("{run}", run_dir)
    kind = spec["kind"]
    if kind == "exists":
        return env.exists(path)
    if kind == "link":
        target = env.link_target(path)
        return target is not None and spec.get("contains", "") in target
    data = env.read(path)
    if kind == "lines":
        return 0 if data is None else data.count(b"\n")
    return data is not None and spec.get("contains", "").encode() in data


CLAUDE_STATUSES = ("busy", "shell", "waiting", "idle")


def claude_sessions(env):
    """Each Claude Code session by its pid: `status` and `statusUpdatedAt`
    of `~/.claude/sessions/<pid>.json`. Nothing else of the file is
    looked at or kept: it holds the folder and the name of the session.
    A status that is not one of the four known words is "other"."""
    folder = config.claude_sessions_dir()
    found = {}
    for name in env.names(folder):
        if not name.endswith(".json") or not name[:-5].isdigit():
            continue
        data = env.read(os.path.join(folder, name))
        try:
            session = json.loads(data) if data else None
        except ValueError:
            continue
        if not isinstance(session, dict) or not isinstance(session.get("status"), str):
            continue
        at = session.get("statusUpdatedAt")
        found[int(name[:-5])] = {
            "status": session["status"] if session["status"] in CLAUDE_STATUSES else "other",
            # Milliseconds since the epoch.
            "at": at / 1000 if isinstance(at, (int, float)) and not isinstance(at, bool) else None,
        }
    return found


def follow(sessions, pid, since):
    """(pid, what the sample keeps of it) of the Claude Code session a
    run follows: the first one whose status became `shell` after the run
    began, and from then on that one. (None, None) while there is none."""
    if pid is None:
        fresh = [(session["at"], number) for number, session in sessions.items()
                 if session["status"] == "shell" and session["at"] is not None and session["at"] >= since]
        if not fresh:
            return None, None
        pid = max(fresh)[1]
    return pid, dict(sessions.get(pid, {"status": "gone", "at": None}), pid=pid)


def take(env, test=None, run_dir="", step=0, children=None):
    """The sample at this moment."""
    app_path = getattr(env, "app", None)
    pids = parse.app_pids(env.command(("ps", "-axo", "pid=,comm="))[1], app_path)
    state = app_state(env, pids)
    # A lab recording runs the same binary: the state names the app.
    pid = state["app"]["pid"] if state else (pids[0] if pids else None)
    battery = parse.battery(env.command(("pmset", "-g", "batt"))[1])
    held = parse.assertions(env.command(("pmset", "-g", "assertions"))[1], pid)
    sample = {
        "t": round(env.now(), 3), "step": step,
        "sleepdisabled": parse.sleep_disabled(env.command(("pmset", "-g"))[1]),
        "power": battery["power"], "charge": battery["charge"],
        "lid": parse.lid(env.command(("ioreg", "-r", "-k", "AppleClamshellState", "-d", "4"))[1]),
        "assertions": held["ours"], "others": held["others"],
        "app_pid": pid, "copies": len(pids), "app": state, "status": status(env, pid),
    }
    if test is None or "sched" in test.get("watch", []):
        events = parse.schedule(env.command(("pmset", "-g", "sched"))[1])
        # The owners of other apps are not kept.
        known = (config.WAKE_OWNER, "pmset")
        sample["sched"] = [{"kind": event["kind"], "owner": event["owner"] if event["owner"] in known else "other"} for event in events]
    if test and test.get("probes"):
        sample["probe"] = {name: probe(env, spec, run_dir) for name, spec in test["probes"].items()}
    if children:
        sample["child"] = {name: "running" if child.poll() is None else "exited" for name, child in children.items()}
    return sample


def holding(sample):
    """True when Agent Caffeine keeps the Mac awake in this sample, False
    when it does not, None when nobody knows. Without the state of the
    app the status file says it."""
    app = sample.get("app")
    if app:
        return bool(app["decision"].get("hold"))
    status = sample.get("status")
    return status["awake"] if status else None


def installed_build(env):
    """"1.0.3 (17)" of the app in the Applications folder, or None."""
    app_path = getattr(env, "app", None)
    data = env.read(app_path + "/Contents/Info.plist") if app_path else None
    if not data:
        return None
    try:
        info = plistlib.loads(data)
    except Exception:
        return None
    return f"{info.get('CFBundleShortVersionString', '?')} ({info.get('CFBundleVersion', '?')})"


def has_state_export(env):
    """True when the installed command line tool knows the switch of the
    state for tests: the build has the export."""
    app_path = getattr(env, "app", None)
    if not app_path:
        return False
    # The tool of a build with the export knows the option --detail. The key
    # of the switch is too short to be found as text in a Swift binary.
    data = env.read(app_path + "/" + config.TOOL_BINARY, limit=64 << 20)
    return data is not None and b"--detail" in data
    # The key of the switch is in the app, which reads it, and not in the tool.
    for binary in (config.TOOL_BINARY, "Contents/MacOS/caffeinagent"):
        data = env.read(app_path + "/" + binary, limit=64 << 20)
        if data is not None and config.SWITCH_KEY.encode() in data:
            return True
    return False


def holds(env):
    """The ids of the holds from the command line, as the tool lists them."""
    answer = env.tool(["status", "--json"])
    if not answer:
        return []
    try:
        return [hold["id"] for hold in json.loads(answer[1].splitlines()[0]).get("holds", [])]
    except (ValueError, IndexError, KeyError, TypeError):
        return []
