"""The tests are data: one TOML file per test in tests/<area>/<id>.toml.

    id, title, layer, area, minutes, risk, why
    heartbeat = true          a writer of time stamps runs during the test
    lab = true                a lab recording of the app binary runs too
    watch = ["sched"]         also sample `pmset -g sched` every second
    [needs]                   power, charge, helper, display, agents, wake_for_jobs
    [probes.<name>]           a look at one of our own files
    [[steps]]                 say, and what ends the step
    checks = [...]            the pass rules, see judge.py
    [[cleanup]]               expect, tell

A step ends with `until` (a condition the runner sees), `key = "enter"`
(the owner says it is done), `ask` (a yes or no question, stored under
`name`), or at once when it has none of them. Before it waits, a step can
`run` or `spawn` the command line tool, `signal` a spawned one, and
`write` a file into the folder of the run.
"""
import os
import re
import tomllib

from . import config, expr, judge

TOP = {"id", "title", "layer", "area", "minutes", "risk", "why", "heartbeat", "lab", "watch", "needs", "probes", "steps", "checks",
       "cleanup", "decides", "overnight"}
NEEDS = {"power", "charge", "helper", "display", "agents", "wake_for_jobs", "app"}
STEP = {"say", "until", "timeout", "key", "ask", "name", "run", "spawn", "signal", "write", "in_minutes", "command", "optional"}
PROBE_KINDS = {"exists", "contains", "lines", "link"}
TOOL = "agent-caffeine"
SIGNALS = {"KILL", "STOP", "CONT", "INT", "TERM"}
WRITES = {"launchd-job"}
JOB_LABEL = "com.caffeinagent.actest.job"
DEFAULT_TIMEOUT = 300


class TestError(ValueError):
    pass


def probe_path_allowed(path):
    """A probe reads our own files only: the skill of Agent Caffeine in a
    skills folder, the link to the tool, the plist of the test job, and
    what is in the folder of the run."""
    if path.startswith("{run}/"):
        return ".." not in path
    if not path.startswith("~/") or ".." in path:
        return False
    return (
        path.endswith("/skills/agent-caffeine/SKILL.md") or path.endswith("/skills/agent-caffeine")
        or path == "~/.local/bin/agent-caffeine" or path == f"~/Library/LaunchAgents/{JOB_LABEL}.plist"
    )


def _unknown(table, allowed, where):
    extra = sorted(set(table) - allowed)
    if extra:
        raise TestError(f"{where}: unknown key {', '.join(extra)}")


def _condition(text, where):
    try:
        expr.check(text)
    except expr.ExprError as error:
        raise TestError(f"{where}: {error}") from error


def validate(test, path="test"):
    """Raises TestError with the file and the reason. Returns the test
    with its defaults filled in."""
    _unknown(test, TOP, path)
    for key in ("id", "title", "layer", "area", "minutes", "steps", "checks"):
        if key not in test:
            raise TestError(f"{path}: {key} is missing")
    if not re.fullmatch(r"[A-Z]+(-[A-Z0-9]+)+", test["id"]):
        raise TestError(f"{path}: the id {test['id']!r} is not like HELP-03")
    needs = test.setdefault("needs", {})
    _unknown(needs, NEEDS, f"{path} needs")
    if needs.get("power", "any") not in ("any", "ac", "battery"):
        raise TestError(f"{path} needs: power is any, ac or battery")
    for name, probe in test.setdefault("probes", {}).items():
        if probe.get("kind") not in PROBE_KINDS:
            raise TestError(f"{path} probe {name}: kind is one of {', '.join(sorted(PROBE_KINDS))}")
        if not probe_path_allowed(probe.get("path", "")):
            raise TestError(f"{path} probe {name}: this path is not one of our own files")
    if not test["steps"]:
        raise TestError(f"{path}: a test has one step at least")
    names = set()
    for number, step in enumerate(test["steps"], 1):
        where = f"{path} step {number}"
        _unknown(step, STEP, where)
        if "say" not in step:
            raise TestError(f"{where}: say is missing")
        if sum(key in step for key in ("until", "key", "ask")) > 1:
            raise TestError(f"{where}: one of until, key and ask")
        if "until" in step:
            _condition(step["until"], where)
        if step.get("key", "enter") != "enter":
            raise TestError(f"{where}: key is \"enter\"")
        if "ask" in step and "name" not in step:
            raise TestError(f"{where}: a question needs a name for its answer")
        for key in ("run", "spawn"):
            if key in step:
                command = step[key]
                if not isinstance(command, list) or not command or command[0] != TOOL:
                    raise TestError(f"{where}: {key} starts {TOOL} and nothing else")
                if "name" not in step:
                    raise TestError(f"{where}: {key} needs a name")
        if "signal" in step and (step["signal"] not in SIGNALS or "name" not in step):
            raise TestError(f"{where}: signal is one of {', '.join(sorted(SIGNALS))} and needs the name of a spawned command")
        if "write" in step and step["write"] not in WRITES:
            raise TestError(f"{where}: write is one of {', '.join(sorted(WRITES))}")
        if "name" in step:
            names.add(step["name"])
        step.setdefault("timeout", DEFAULT_TIMEOUT)
    for text in test["checks"]:
        try:
            _, form, groups = judge.parse_check(text)
        except judge.CheckError as error:
            raise TestError(f"{path} checks: {error}") from error
        for number in re.findall(r"step (\d+)", text):
            if not 1 <= int(number) <= len(test["steps"]):
                raise TestError(f"{path} checks: there is no step {number}: {text!r}")
        if form in ("key", "exit", "out") and groups[0] not in names:
            raise TestError(f"{path} checks: no step has the name {groups[0]}: {text!r}")
    for entry in test.setdefault("cleanup", []):
        _unknown(entry, {"expect", "tell"}, f"{path} cleanup")
        if "expect" not in entry or "tell" not in entry:
            raise TestError(f"{path} cleanup: expect and tell")
        _condition(entry["expect"], f"{path} cleanup")
    for text in [step.get("until", "") for step in test["steps"]] + test["checks"] + [entry["expect"] for entry in test["cleanup"]]:
        for name in re.findall(r"probe\.(\w+)", text):
            if name not in test["probes"]:
                raise TestError(f"{path}: there is no probe {name}")
    test.setdefault("watch", [])
    test.setdefault("heartbeat", False)
    test.setdefault("lab", False)
    return test


def load_file(path):
    with open(path, "rb") as file:
        try:
            test = tomllib.load(file)
        except tomllib.TOMLDecodeError as error:
            raise TestError(f"{path}: {error}") from error
    test = validate(test, os.path.relpath(path, config.HERE))
    if os.path.basename(path) != test["id"] + ".toml":
        raise TestError(f"{path}: the file of {test['id']} is named {test['id']}.toml")
    if os.path.basename(os.path.dirname(path)) != test["area"]:
        raise TestError(f"{path}: the folder is the area, {test['area']}")
    return test


def load_all(root=None):
    """Every test, by id. Raises TestError for the first file that is wrong."""
    tests = {}
    root = root or config.TESTS_DIR
    for folder, _, names in sorted(os.walk(root)):
        for name in sorted(names):
            if name.endswith(".toml"):
                test = load_file(os.path.join(folder, name))
                if test["id"] in tests:
                    raise TestError(f"{test['id']} is in two files")
                tests[test["id"]] = test
    return tests


def select(tests, area=None, layer=None):
    return [test for test in tests.values() if (area is None or test["area"] == area) and (layer is None or test["layer"] == layer)]
