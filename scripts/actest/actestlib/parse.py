"""Readers of the text that macOS tools print. Pure: text in, values out."""
import re
from datetime import datetime

LOG_KINDS = ("Sleep", "Wake", "DarkWake", "Notification")
_LOG_LINE = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d [+-]\d{4}) ([A-Za-z.]+(?: [A-Za-z]+)?)\s*\t(.*)$")


def sleep_disabled(text):
    """The SleepDisabled line of `pmset -g`. None when it is not there."""
    match = re.search(r"^\s*SleepDisabled\s+(\d)", text, re.M)
    return int(match.group(1)) if match else None


def timers(text):
    """The sleep and display timers of `pmset -g`, in minutes."""
    found = {}
    for name in ("sleep", "displaysleep"):
        match = re.search(rf"^\s*{name}\s+(\d+)", text, re.M)
        if match:
            found[name] = int(match.group(1))
    return found


def battery(text):
    """`pmset -g batt`: the power source and the charge."""
    source = None
    if "'AC Power'" in text:
        source = "ac"
    elif "'Battery Power'" in text:
        source = "battery"
    match = re.search(r"(\d+)%", text)
    return {"power": source, "charge": int(match.group(1)) if match else None}


def lid(text):
    """`ioreg -r -k AppleClamshellState -d 4`."""
    match = re.search(r'"AppleClamshellState"\s*=\s*(Yes|No)', text)
    if not match:
        return None
    return "closed" if match.group(1) == "Yes" else "open"


def assertions(text, pid):
    """`pmset -g assertions`: the kinds our app holds, and the names of the
    other processes that hold one. Never the text of an assertion."""
    ours, others = [], set()
    for match in re.finditer(r"^\s*pid (\d+)\(([^)]*)\): \[[^\]]*\] \S+ (\w+) named:", text, re.M):
        kind = match.group(3)
        if not kind.startswith("Prevent"):
            continue
        if pid is not None and int(match.group(1)) == pid:
            ours.append(kind)
        else:
            others.add(match.group(2))
    return {"ours": sorted(ours), "others": sorted(others)}


def schedule(text):
    """`pmset -g sched`: each event with its kind and its owner."""
    events = []
    for match in re.finditer(r"^\s*\[\d+\]\s+(\w+) at (\S+ \S+)(?: by '([^']*)')?", text, re.M):
        events.append({"kind": match.group(1), "at": match.group(2), "owner": match.group(3) or ""})
    return events


def app_pids(text, app_path):
    """`ps -axo pid=,comm=`: the pids that run the binary of the app in the
    Applications folder. More than one: a lab recording runs too."""
    if not app_path:
        return []
    wanted = (app_path + "/Contents/MacOS/caffeinagent").lower()
    pids = []
    for line in text.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[1].lower() == wanted:
            pids.append(int(parts[0]))
    return pids


def external_displays(profile):
    """`system_profiler SPDisplaysDataType -json`, parsed: how many
    displays are not the built-in one."""
    count = 0
    for card in profile.get("SPDisplaysDataType", []):
        for display in card.get("spdisplays_ndrvs", []):
            if display.get("spdisplays_connection_type") != "spdisplays_internal":
                count += 1
    return count


def power_log(text, start, end):
    """`pmset -g log` cut to a time window: the lines of sleep, wake and
    display only. The assertion lines hold names of other apps and stay out."""
    lines = []
    for line in text.splitlines():
        match = _LOG_LINE.match(line)
        if not match or match.group(2) not in LOG_KINDS:
            continue
        at = datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S %z").timestamp()
        if start <= at <= end:
            lines.append({"t": at, "kind": match.group(2), "text": match.group(3).strip()})
    return lines


def heartbeat_gap(stamps, start, end):
    """The largest hole between two stamps in the window, in seconds. The
    window edges count: a writer that never wrote is one hole."""
    inside = [stamp for stamp in stamps if start <= stamp <= end]
    points = [start] + inside + [end]
    return max(later - earlier for earlier, later in zip(points, points[1:]))
