"""After a test, and after Control-C: end what the test started, then
look at what must be true again and tell the owner what is left."""
import os
import signal

from . import expr, sampler, store

BUILT_IN = [
    {"expect": "app.running=true", "tell": "Open Agent Caffeine again."},
    {"expect": "status.stopped=false", "tell": "Switch Agent Caffeine on and end the pause."},
    {"expect": "lid=open", "tell": "Open the lid."},
    {"expect": "sleepdisabled=0 or status.awake=true",
     "tell": "SleepDisabled is still 1 and nothing holds. Wait 65 seconds. If it stays 1, this is a fault: tell the assistant."},
    {"expect": "sched.byhand=false", "tell": "Remove the alarm you set by hand."},
]
WAIT = 90


def end_child(child):
    """Ends a process the runner started, with the command it runs: the
    tool is the leader of a group of its own, and a tool that was killed
    leaves its command in that group. False when nothing was left."""
    alive = child.poll() is None
    try:
        os.killpg(child.pid, signal.SIGTERM)
        return True
    except (OSError, AttributeError, TypeError):
        if alive:
            child.terminate()
        return alive


def run(session, wait=WAIT):
    """Returns what was done and what is left for the owner."""
    env, ui = session.env, session.ui
    actions, left = [], []
    try:
        for name, child in session.children.items():
            if end_child(child):
                actions.append(f"stopped the command {name}")
        for hold in sampler.holds(env):
            if hold not in session.holds_before:
                env.tool(["release", hold])
                actions.append(f"released the hold {hold}")
        if session.heartbeat:
            session.heartbeat.terminate()
            actions.append("stopped the heartbeat")
        if session.lab:
            session.lab.send_signal(signal.SIGINT)
            actions.append("stopped the recording")
        expectations = BUILT_IN + session.test["cleanup"]
        watched = dict(session.test, watch=session.test.get("watch", []) + ["sched"])
        deadline = env.now() + wait
        shown = None
        while True:
            found = session.sample(watched, step=-1)
            left = [entry["tell"] for entry in expectations if not expr.holds(entry["expect"], found)]
            if [hold for hold in sampler.holds(env) if hold not in session.holds_before]:
                left.append("Run: agent-caffeine release --all")
            if not left or env.now() >= deadline:
                break
            if left != shown:
                ui.page(f"{session.test['id']}   cleanup")
                for tell in left:
                    ui.line(tell)
                ui.line()
                ui.line("The runner sees it when it is done.   [Enter] go on without it")
                shown = left
            if env.key(1.0) == "enter":
                break
    except KeyboardInterrupt:
        pass
    store.clear_active()
    return {"actions": actions, "left": left}


def _alive(pid):
    try:
        os.kill(pid, 0)
    except (OSError, TypeError):
        return False
    return True


def abort(env, ui, command_of, wait=20):
    """`actest abort`: tells the run that is under way to stop, or cleans
    up after one that is gone. Only processes the runner started are
    ended, and only when their command still says so."""
    info = store.active()
    if not info:
        ui.line("No test runs.")
        return 0
    pid = info.get("pid")
    if _alive(pid) and "actest" in command_of(pid):
        os.kill(pid, signal.SIGINT)
        ui.line(f"The run of {info.get('test')} was told to stop. Its cleanup shows in its own Terminal.")
        deadline = env.now() + wait
        while store.active() and env.now() < deadline:
            env.sleep(0.5)
        return 0
    marks = {"heartbeat": "actestlib.heartbeat", "lab": "--lab-record"}
    for name, child in (info.get("procs") or {}).items():
        if _alive(child) and marks.get(name, "agent-caffeine") in command_of(child):
            os.kill(child, signal.SIGINT if name == "lab" else signal.SIGTERM)
            ui.line(f"Stopped {name}.")
    for hold in sampler.holds(env):
        if hold not in (info.get("holds_before") or []):
            env.tool(["release", hold])
            ui.line(f"Released the hold {hold}.")
    found = sampler.take(env)
    for entry in BUILT_IN:
        if not expr.holds(entry["expect"], found):
            ui.line(f"Still to do: {entry['tell']}")
    run_dir = info.get("run")
    if run_dir and os.path.isdir(run_dir) and not os.path.exists(os.path.join(run_dir, "verdict.json")):
        store.write_verdict(run_dir, {"test": info.get("test"), "result": "aborted", "reason": "the runner was gone", "checks": [],
                                      "ended": env.now(), "run": os.path.basename(run_dir)})
    store.clear_active()
    ui.line("The run is cleaned up.")
    return 0
