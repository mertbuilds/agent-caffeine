"""The pass rules of a test, as small sentences over what was recorded.

    within 10s after step 2: app.agent[grok].state=working
    always from step 2 to step 3: app.hold=true
    never from start to end: app.safety!=none
    at end: sleepdisabled=0
    heartbeat gap from step 2 to step 3 < 15s
    log from step 2 to step 3 has no Sleep,DarkWake
    log within 60s after step 4 has Sleep
    key chime is yes
    exit seven == 7
    out refused contains not running

A moment is `start`, `end`, `step N` (when step N ended) or `step N start`,
with `+ 30s` or `- 5s` after it. `info ` in front makes a rule that only
measures and never fails.
"""
import re

from . import expr, parse

_REF = r"(start|end|step \d+(?: start)?)(?:\s*([+-])\s*(\d+(?:\.\d+)?[smh]?))?"
_FORMS = [
    ("within", re.compile(rf"^within (\S+) after {_REF}: (.+)$")),
    ("always", re.compile(rf"^always from {_REF} to {_REF}: (.+)$")),
    ("never", re.compile(rf"^never from {_REF} to {_REF}: (.+)$")),
    ("at", re.compile(rf"^at {_REF}: (.+)$")),
    ("gap", re.compile(rf"^heartbeat gap from {_REF} to {_REF} < (\S+)$")),
    ("log", re.compile(rf"^log from {_REF} to {_REF} has (no )?([A-Za-z,]+)$")),
    ("logwithin", re.compile(rf"^log within (\S+) after {_REF} has (no )?([A-Za-z,]+)$")),
    ("key", re.compile(r"^key (\w+) is (\w+)$")),
    ("exit", re.compile(r"^exit (\w+) == (-?\d+)$")),
    ("out", re.compile(r"^out (\w+) contains (.+)$")),
]


class CheckError(ValueError):
    pass


def parse_check(text):
    """(info, form, groups). Raises CheckError for a rule that cannot be read."""
    body = text.strip()
    info = body.startswith("info ")
    if info:
        body = body[5:].strip()
    for form, pattern in _FORMS:
        match = pattern.match(body)
        if match:
            groups = match.groups()
            if form in ("within", "always", "never", "at"):
                try:
                    expr.check(groups[-1])
                except expr.ExprError as error:
                    raise CheckError(str(error)) from error
            return info, form, groups
    raise CheckError(f"cannot read the rule: {text!r}")


def moment(evidence, name, sign=None, offset=None):
    """The time of a named moment. None when the run never got there."""
    if name in ("start", "end"):
        base = evidence.get(name)
    else:
        match = re.match(r"step (\d+)( start)?", name)
        step = next((step for step in evidence.get("steps", []) if step["n"] == int(match.group(1))), None)
        base = step.get("start" if match.group(2) else "end") if step else None
    if base is None:
        return None
    shift = expr.literal(offset) if offset else 0
    return base - shift if sign == "-" else base + shift


def _window(evidence, first, last):
    return [sample for sample in evidence.get("samples", []) if first <= sample["t"] <= last]


def _judge(evidence, form, groups):
    if form == "key":
        answer = evidence.get("keys", {}).get(groups[0])
        return answer == groups[1], f"answer: {answer or 'none'}"
    if form in ("exit", "out"):
        command = evidence.get("commands", {}).get(groups[0])
        if command is None:
            return False, "the command did not run"
        if form == "exit":
            return command.get("code") == int(groups[1]), f"exit code {command.get('code')}"
        found = groups[1].strip().lower() in (command.get("out") or "").lower()
        return found, "the text is there" if found else "the text is not there"
    if form in ("within", "logwithin"):
        first = moment(evidence, *groups[1:4])
        last = None if first is None else first + expr.literal(groups[0])
        rest = groups[4:]
    elif form == "at":
        first = last = moment(evidence, *groups[0:3])
        rest = groups[3:]
    else:
        first, last = moment(evidence, *groups[0:3]), moment(evidence, *groups[3:6])
        rest = groups[6:]
    if first is None or last is None:
        return False, "the run did not reach this step"
    if form == "gap":
        gap = parse.heartbeat_gap(evidence.get("heartbeat", []), first, last)
        return gap < expr.literal(rest[0]), f"largest gap {gap:.0f} s"
    if form in ("log", "logwithin"):
        if evidence.get("log") is None:
            return False, "the power log was not read"
        kinds = rest[1].split(",")
        lines = [line for line in evidence["log"] if first <= line["t"] <= last and line["kind"] in kinds]
        wanted = rest[0] is None
        said = f"{len(lines)} line{'' if len(lines) == 1 else 's'} of {rest[1]}"
        if lines:
            said += f", first after {lines[0]['t'] - first:.0f} s"
        return bool(lines) == wanted, said
    condition = rest[0]
    if form == "at":
        after = [sample for sample in evidence.get("samples", []) if sample["t"] >= first]
        if not after:
            return False, "no sample at that moment"
        return expr.holds(condition, after[0], first), expr.reading(condition, after[0], first)
    samples = _window(evidence, first, last)
    if not samples:
        return False, "no sample in the window"
    hits = [sample for sample in samples if expr.holds(condition, sample, first)]
    if form == "within":
        if hits:
            return True, f"true after {hits[0]['t'] - first:.0f} s"
        return False, f"not true in {last - first:.0f} s, last: {expr.reading(condition, samples[-1], first)}"
    if form == "never":
        if hits:
            return False, f"true after {hits[0]['t'] - first:.0f} s, in {len(hits)} of {len(samples)} samples"
        return True, f"false in all {len(samples)} samples"
    misses = [sample for sample in samples if not expr.holds(condition, sample, first)]
    if misses:
        said = f"false after {misses[0]['t'] - first:.0f} s, in {len(misses)} of {len(samples)} samples"
        return False, f"{said}: {expr.reading(condition, misses[0], first)}"
    return True, f"true in all {len(samples)} samples"


def judge(evidence, checks):
    """One result per rule: the rule, pass or fail, and what was measured."""
    results = []
    for text in checks:
        info, form, groups = parse_check(text)
        ok, measured = _judge(evidence, form, groups)
        results.append({"check": text, "ok": True if info else ok, "info": info, "measured": measured})
    return results


def verdict(results, problem=None):
    """(result, reason): the first rule that failed, with its value. A
    pass shows the first rule that measured something."""
    if problem:
        return "fail", problem
    failed = next((result for result in results if not result["ok"]), None)
    if failed:
        return "fail", f"{failed['check']} ({failed['measured']})"
    shown = next((result for result in results if not result["info"]), None)
    return "pass", f"{shown['check']} ({shown['measured']})" if shown else "no rule to check"
