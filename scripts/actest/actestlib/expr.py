"""Small expressions over one sample of the timeline.

    lid=closed            power=battery         sleepdisabled=1
    app.hold=true         app.agent[grok].state=working
    time>=30s             app.running=false and sleepdisabled=0

A term is `path op value`. Terms join with `and`, and groups of them with
`or`. A path that has no value compares equal to `none` and to nothing else.
"""
import re

from . import config

_TERM = re.compile(r"^\s*([\w.\[\]*:-]+)\s*(==|!=|>=|<=|=|>|<)\s*(\S+)\s*$")
_INDEXED = re.compile(r"^(\w+)\[([^\]]+)\](?:\.(\w+))?$")
_ORDER = {"working": 3, "waiting": 2, "idle": 1}
_APP = {
    "hold": ("decision", "hold"), "headline": ("decision", "headline"), "reason": ("decision", "reason"),
    "stop": ("decision", "stop"), "assertion": ("decision", "assertion"), "on": ("on",), "mode": ("mode",),
    "flag": ("flag", "set"), "wanted": ("flag", "wanted"), "helper": ("flag", "helper"), "setup": ("flag", "setup"),
    "gate": ("gate",), "safety": ("safety",), "entitlement": ("entitlement",), "lid": ("lid", "closed"),
    "power": ("power", "source"), "charge": ("power", "percent"), "pid": ("app", "pid"),
    "version": ("app", "version"), "build": ("app", "build"),
}


class ExprError(ValueError):
    pass


def literal(text):
    low = text.lower()
    if low in ("true", "yes"):
        return True
    if low in ("false", "no"):
        return False
    if low in ("none", "null"):
        return None
    match = re.fullmatch(r"(-?\d+(?:\.\d+)?)(s|m|h|%)?", low)
    if match:
        number = float(match.group(1)) * {"m": 60, "h": 3600}.get(match.group(2), 1)
        return int(number) if number == int(number) else number
    return text


def _dig(value, keys):
    for key in keys:
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return value


def _agent(app, name, field):
    rows = [row for row in app.get("agents", []) if name == "*" or row.get("id") == name]
    if field == "count":
        return len(rows)
    if not rows:
        return "gone" if field in (None, "state") else None
    best = max(rows, key=lambda row: _ORDER.get(row.get("state"), 0))
    return best.get(field or "state")


def _events(events, kind, field, now):
    found = [event for event in events or [] if event.get("kind") == kind]
    if field == "age":
        return now - max(event["at"] for event in found) if found else None
    return len(found)


def _app(sample, rest, now):
    app = sample.get("app")
    if rest == "running":
        return sample.get("app_pid") is not None
    if rest == "state":
        return app is not None
    if app is None:
        return None
    if rest in _APP:
        return _dig(app, _APP[rest])
    if rest == "paused":
        return app.get("pausedUntil") is not None
    if rest == "holds":
        return len(app.get("holds", []))
    if rest == "jobholds":
        return len(_dig(app, ("jobs", "holds")) or [])
    if rest == "alarm":
        return _dig(app, ("jobs", "alarm")) is not None
    if rest == "chime.age":
        return now - app["chimeAt"] if app.get("chimeAt") else None
    match = _INDEXED.match(rest)
    if match and match.group(1) == "agent":
        return _agent(app, match.group(2), match.group(3))
    if match and match.group(1) == "notice":
        return _events(app.get("notices"), match.group(2), match.group(3), now)
    if match and match.group(1) == "history":
        return _events(_dig(app, ("jobs", "history")), match.group(2), match.group(3), now)
    return _dig(app, rest.split("."))


def value(sample, path, since=None):
    """What a path reads in one sample. `since` is the start of the step
    or of the window, for `time`."""
    now = sample.get("t", 0)
    if path == "time":
        return now - (since if since is not None else now)
    if path in ("lid", "power", "charge", "sleepdisabled"):
        return sample.get(path)
    if path == "assertions":
        return len(sample.get("assertions") or [])
    if path == "others":
        return len(sample.get("others") or [])
    if path in ("sched.ours", "sched.byhand"):
        owner = config.WAKE_OWNER if path == "sched.ours" else "pmset"
        events = sample.get("sched")
        return None if events is None else any(event.get("owner") == owner for event in events)
    head, _, rest = path.partition(".")
    if head == "app":
        return _app(sample, rest, now)
    if head in ("status", "probe", "child"):
        return _dig(sample.get(head), rest.split("."))
    raise ExprError(f"unknown path {path}")


def _compare(left, op, right):
    if op in ("=", "=="):
        if isinstance(left, bool) or isinstance(right, bool) or left is None or right is None:
            return left is right
        if _number(left) and _number(right):
            return left == right
        return str(left) == str(right)
    if op == "!=":
        return not _compare(left, "==", right)
    if not (_number(left) and _number(right)):
        return False
    return {">=": left >= right, "<=": left <= right, ">": left > right, "<": left < right}[op]


def _number(item):
    return isinstance(item, (int, float)) and not isinstance(item, bool)


def terms(text):
    """The parsed form: a list of groups, each a list of (path, op, value)."""
    groups = []
    for group in re.split(r"\s+or\s+", text.strip()):
        parsed = []
        for term in re.split(r"\s+and\s+", group):
            match = _TERM.match(term)
            if not match:
                raise ExprError(f"cannot read the condition: {term!r}")
            parsed.append((match.group(1), match.group(2), literal(match.group(3))))
        groups.append(parsed)
    return groups


def holds(text, sample, since=None):
    """True when the condition is true in the sample."""
    return any(all(_compare(value(sample, path, since), op, want) for path, op, want in group) for group in terms(text))


def reading(text, sample, since=None):
    """What the paths of a condition read, for the measured value."""
    seen = []
    for group in terms(text):
        for path, _, _ in group:
            entry = f"{path}={show(value(sample, path, since))}"
            if entry not in seen:
                seen.append(entry)
    return ", ".join(seen)


def show(item):
    if item is None:
        return "none"
    if isinstance(item, bool):
        return "true" if item else "false"
    if isinstance(item, float):
        return f"{item:.1f}"
    return str(item)


def check(text):
    """Raises ExprError for a condition that cannot be read. For the
    loader of the test files."""
    empty = {"t": 0, "app": None}
    for group in terms(text):
        for path, _, _ in group:
            value(empty, path)
