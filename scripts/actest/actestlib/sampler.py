"""One sample of the watches: what the Mac and the app say at one moment."""
import json
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
    data = env.read(app_path + "/" + config.TOOL_BINARY, limit=64 << 20) if app_path else None
    return data is not None and config.SWITCH_KEY.encode() in data


def holds(env):
    """The ids of the holds from the command line, as the tool lists them."""
    answer = env.tool(["status", "--json"])
    if not answer:
        return []
    try:
        return [hold["id"] for hold in json.loads(answer[1].splitlines()[0]).get("holds", [])]
    except (ValueError, IndexError, KeyError, TypeError):
        return []
