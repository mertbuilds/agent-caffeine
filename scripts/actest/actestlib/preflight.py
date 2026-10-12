"""The preflight: what must be true before a test starts. Each item is
pass, fail, unknown or a note, with the one action that fixes it."""
import json

from . import config, parse, sampler

GENERIC = {"helper": True}
MIN_CHARGE = 30


def gather(env):
    """What the checks need, read once. Nothing here changes the Mac."""
    switch = env.command(("defaults", "read", config.BUNDLE_ID, config.SWITCH_KEY))
    try:
        displays = parse.external_displays(json.loads(env.command(("system_profiler", "SPDisplaysDataType", "-json"))[1]))
    except ValueError:
        displays = None
    return {
        "sample": sampler.take(env),
        "installed": sampler.installed_build(env),
        "expected": config.expected_build(),
        "export": sampler.has_state_export(env),
        "switch": switch[0] == 0 and switch[1].strip() == "1",
        "holds": sampler.holds(env),
        "limits": sampler.test_limits(env),
        "displays": displays,
        "free": env.free_bytes(),
        "timers": parse.timers(env.command(("pmset", "-g"))[1]),
        "active": env.exists(config.active_file()),
    }


def _item(name, status, text, fix=None):
    return {"name": name, "status": status, "text": text, "fix": fix}


def check(facts, test=None):
    """The items in order. A test that names no need gets the usual ones."""
    needs = dict(GENERIC if test is None else {}, **(test or {}).get("needs", {}))
    sample = facts["sample"]
    app = sample.get("app")
    status = sample.get("status") or {}
    items = []

    def add(name, ok, text, fix=None):
        items.append(_item(name, "pass" if ok else "fail", text, None if ok else fix))

    def unknown(name, text):
        items.append(_item(name, "unknown", text, "Needs the state export of the app."))

    installed, expected = facts["installed"], facts["expected"]
    if installed is None:
        add("build", False, "Agent Caffeine is not in the Applications folder", "Install the build under test.")
    else:
        add("build", expected is None or installed == expected, f"installed build is {installed}", f"Install build {expected}.")
    running = sample.get("app_pid") is not None
    add("running", running, "Agent Caffeine runs" if running else "Agent Caffeine does not run", "Open Agent Caffeine.")
    add("export", facts["export"], "installed build has the state export" if facts["export"] else
        "installed build has no state export: install the new build", "Install the build of this branch, then run actest check again.")
    add("switch", facts["switch"], "StateForTests is on" if facts["switch"] else "StateForTests is off", f"Run: {config.SWITCH_ON}")
    if facts["export"] and facts["switch"] and running:
        add("state", app is not None, "the app writes its state" if app else "the app wrote no fresh state",
            "Wait 10 seconds and check again. If it stays: quit Agent Caffeine and open it.")

    # A test that only needs the Mac to sleep can start with the app off.
    sleeps = bool(needs.get("sleeps"))
    if app:
        on = app.get("on") and app.get("pausedUntil") is None
        add("on", on or sleeps, "switched on, no pause" if on else "switched off or paused", "Switch Agent Caffeine on and end the pause.")
    elif running:
        stopped = status.get("stopped")
        add("on", stopped is False or sleeps, "no stop is in force" if stopped is False else "a stop is in force: off, paused or a safety stop",
            "Switch Agent Caffeine on and end the pause.")

    helper = (app or {}).get("flag", {}).get("helper")
    if needs.get("helper"):
        if app:
            add("helper", helper == "enabled", f"helper: {helper}", "Settings > Battery and lid: set up the helper.")
        else:
            unknown("helper", "the state of the helper is not known")

    holding = sampler.holding(sample)
    held = "Agent Caffeine holds now" + (f": {app['decision'].get('headline')}" if app else "")
    if needs.get("idle"):
        if holding is None:
            unknown("idle", "it is not known if an agent works now")
        else:
            add("idle", not holding, "nothing holds the Mac awake now" if not holding else held,
                "Wait until no agent works, or close the agents that work. Then check again.")
    if sleeps:
        if holding is None:
            unknown("sleeps", "it is not known if Agent Caffeine holds now")
        else:
            add("sleeps", not holding, "Agent Caffeine does not hold: the Mac can sleep" if not holding else held,
                "Pause Agent Caffeine or switch it off for this test.")

    flag = sample.get("sleepdisabled")
    if app:
        wanted = 1 if app["flag"].get("wanted") and helper == "enabled" else 0
        add("flag", flag == wanted, f"SleepDisabled is {flag}, the app wants {wanted}",
            "Wait 65 seconds and check again. If it stays, do not test: tell the assistant.")
    else:
        awake = status.get("awake")
        add("flag", flag == 0 or (flag == 1 and awake is True), f"SleepDisabled is {flag}" + (", and the app holds" if flag == 1 and awake else ""),
            "SleepDisabled is 1 and nothing of Agent Caffeine holds. Wait 65 seconds and check again. If it stays, someone else set it.")

    holds = facts["holds"]
    add("holds", not holds, "no leftover hold" if not holds else f"{len(holds)} leftover hold from the command line", "Run: agent-caffeine release --all")
    # The test of a limit sets it in its first step, and may start with it.
    limits = [key for key in facts["limits"] if (test or {}).get("id") != config.LIMITS[key]]
    add("limit", not limits, "no leftover test limit" if not limits else "a test limit is still set",
        "Run: " + ", then: ".join(config.limit_off(key) for key in limits))
    copies = sample.get("copies", 0)
    add("recording", copies <= 1 and not facts["active"],
        "no leftover recording or test run" if copies <= 1 and not facts["active"] else "a recording or a test run is still there",
        "Run: actest abort. A lab recording ends with Control-C in its Terminal.")
    events = sample.get("sched") or []
    by_hand = [event for event in events if event["owner"] == "pmset"]
    ours = [event for event in events if event["owner"] == config.WAKE_OWNER]
    jobs_on = (app or {}).get("jobs", {}).get("on", False)
    add("alarm", not by_hand and (not ours or jobs_on),
        "no test alarm in the power schedule" if not by_hand and not ours else f"{len(by_hand)} alarm set by hand, {len(ours)} of Agent Caffeine",
        "Remove the alarm you set by hand yourself (the runner never does). An alarm of Agent Caffeine goes when Wake for jobs is off.")

    power, charge = sample.get("power"), sample.get("charge")
    want = needs.get("power", "any")
    add("power", want == "any" or power == want, f"power source: {power}",
        "Pull the charger." if want == "battery" else "Plug the charger in.")
    floor = needs.get("charge", MIN_CHARGE if power == "battery" else 0)
    add("charge", charge is not None and charge >= floor, f"charge: {charge}%", f"Charge to {floor}% or more.")
    add("lid", sample.get("lid") == "open", f"lid: {sample.get('lid')}", "Open the lid.")
    if needs.get("display") == "builtin":
        add("display", facts["displays"] == 0, "no external display" if facts["displays"] == 0 else f"external displays: {facts['displays']}",
            "Unplug the external display.")
    for agent in needs.get("agents", []):
        if app is None:
            unknown(f"agent {agent}", f"it is not known if {agent} runs")
            continue
        rows = [row for row in app.get("agents", []) if row.get("id") == agent]
        add(f"agent {agent}", bool(rows), f"{agent}: {len(rows)} running" if rows else f"{agent} does not run", f"Open {agent} and sign in.")
    if "wake_for_jobs" in needs:
        if app is None:
            unknown("wake for jobs", "the switch of Wake for jobs is not known")
        else:
            add("wake for jobs", jobs_on == needs["wake_for_jobs"], f"Wake for jobs is {'on' if jobs_on else 'off'}",
                f"Settings > Wake for jobs: switch it {'on' if needs['wake_for_jobs'] else 'off'}.")
    add("disk", facts["free"] >= config.MIN_FREE_BYTES, f"free disk: {facts['free'] / (1 << 30):.0f} GB", "Free 1 GB of disk.")
    others = sample.get("others") or []
    if others:
        items.append(_item("others", "note", f"others keep the Mac awake: {', '.join(others)}"))
    timers = facts["timers"]
    items.append(_item("timers", "note", f"sleep timer {timers.get('sleep', '?')} min, display {timers.get('displaysleep', '?')} min"))
    return items


def free_now(sample, test):
    """True when a test can start as the agents are now: it needs
    nothing of them, or Agent Caffeine holds nothing."""
    needs = test.get("needs", {})
    if needs.get("idle") or needs.get("sleeps"):
        return sampler.holding(sample) is False
    return True


def blocked(items):
    """The items that stop a test: a fail, or something not known."""
    return [item for item in items if item["status"] in ("fail", "unknown")]
