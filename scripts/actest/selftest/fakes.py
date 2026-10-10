"""A fake of the environment: a clock that only moves when the runner
waits, pmset and ioreg that print what a scenario says, a state file of
the app, and the keys of an owner who follows the script."""
import io
import json
import plistlib

from actestlib import config

APP = "/Applications/Agent Caffeine.app"
LOG_STAMP = "%Y-%m-%d %H:%M:%S %z"


class FakeChild:
    def __init__(self, code=None):
        self.code = code
        self.signals = []
        self.pid = 4000

    def poll(self):
        return self.code

    def send_signal(self, number):
        self.signals.append(number)
        self.code = -number

    def terminate(self):
        self.send_signal(15)

    def wait(self, timeout=None):
        return self.code


class FakeEnv:
    """`world(t)` gives what is true at time t (seconds from the start):
    lid, power, charge, flag, pid, state (the dict of the app or None),
    sched, others. `keys` maps a time to the key pressed then."""

    def __init__(self, world, keys=None, export=True, switch=True, build="1.0.3 (17)", start=1_800_000_000.0):
        self.app = APP
        self.world = world
        self.keys = dict(keys or {})
        self.export = export
        self.switch = switch
        self.build = build
        self.start = start
        self.clock = start
        self.commands = []
        self.tool_calls = []
        self.tool_answers = {}
        self.spawned = []
        self.files = {}
        self.log_lines = []
        self.holds = []
        self.free = 50 << 30

    @property
    def t(self):
        return self.clock - self.start

    def at(self):
        return dict({"lid": "open", "power": "ac", "charge": 100, "flag": 0, "pid": 500, "state": None, "sched": [], "others": [],
                     "awake": False, "stopped": False, "displays": 0}, **self.world(self.t))

    def now(self):
        return self.clock

    def sleep(self, seconds):
        self.clock += max(0.0, seconds)

    def key(self, timeout):
        for moment in sorted(self.keys):
            if moment <= self.t + timeout:
                self.clock = max(self.clock, self.start + moment)
                return self.keys.pop(moment)
        self.sleep(timeout)
        return None

    def open_keys(self):
        pass

    def close_keys(self):
        pass

    def command(self, args, timeout=20):
        self.commands.append(tuple(args))
        now = self.at()
        if args == ("pmset", "-g"):
            return 0, f"System-wide power settings:\n SleepDisabled\t\t{now['flag']}\nCurrently in use:\n sleep 1\n displaysleep 10\n"
        if args == ("pmset", "-g", "batt"):
            source = "AC Power" if now["power"] == "ac" else "Battery Power"
            return 0, f"Now drawing from '{source}'\n -InternalBattery-0 (id=1)\t{now['charge']}%; x; present: true\n"
        if args == ("pmset", "-g", "assertions"):
            lines = [f'   pid 900({name}): [0x1] 00:00:01 PreventUserIdleSystemSleep named: "x"' for name in now["others"]]
            if now["awake"] and now["pid"]:
                lines.append(f'   pid {now["pid"]}(caffeinagent): [0x2] 00:00:01 PreventSystemSleep named: "Agent Caffeine: x"')
            return 0, "Listed by owning process:\n" + "\n".join(lines) + "\n"
        if args == ("pmset", "-g", "sched"):
            return 0, "Scheduled power events:\n" + "".join(f" [{i}]  wake at 10/11/2026 02:58:24 by '{owner}'\n" for i, owner in enumerate(now["sched"]))
        if args == ("pmset", "-g", "log"):
            return 0, "\n".join(self.log_lines) + "\n"
        if args[0] == "ioreg":
            return 0, f'  |   "AppleClamshellState" = {"Yes" if now["lid"] == "closed" else "No"}\n'
        if args[0] == "ps":
            return 0, f"{now['pid']} {APP}/Contents/MacOS/caffeinagent\n" if now["pid"] else "1 /sbin/launchd\n"
        if args[0] == "defaults":
            return (0, "1\n") if self.switch else (1, "")
        if args[0] == "system_profiler":
            displays = [{"spdisplays_connection_type": "spdisplays_internal"}] + [{"_name": "external"}] * now["displays"]
            return 0, json.dumps({"SPDisplaysDataType": [{"spdisplays_ndrvs": displays}]})
        return 0, "26.7.1\n"

    def read(self, path, limit=1 << 20):
        now = self.at()
        if path == config.state_file():
            if now["state"] is None or not now["pid"]:
                return None
            state = dict(now["state"], at=self.clock)
            state.setdefault("app", {"pid": now["pid"], "version": "1.0.3", "build": "17"})
            return json.dumps(state).encode()
        if path == config.status_file():
            return json.dumps({"v": 1, "awake": now["awake"], "stopped": now["stopped"], "line": "Secret Agent is working"}).encode()
        if path == APP + "/Contents/Info.plist":
            version, build = self.build.rstrip(")").split(" (")
            return plistlib.dumps({"CFBundleShortVersionString": version, "CFBundleVersion": build})
        if path == APP + "/" + config.TOOL_BINARY:
            return b"binary " + (config.SWITCH_KEY.encode() if self.export else b"old") + b" binary"
        return self.files.get(path)

    def exists(self, path):
        return path in self.files

    def link_target(self, path):
        return self.files.get("link:" + path)

    def free_bytes(self):
        return self.free

    def tool(self, args, timeout=30):
        self.tool_calls.append(list(args))
        if args[:1] == ["release"] and len(args) == 2 and args[1] in self.holds:
            self.holds.remove(args[1])
        if args == ["status", "--json"]:
            return 0, json.dumps({"appRunning": True, "holds": [{"id": hold} for hold in self.holds], "line": "x"}) + "\n"
        return self.tool_answers.get(args[0], (0, ""))

    def spawn_tool(self, args):
        self.tool_calls.append(list(args))
        self.spawned.append(FakeChild())
        return self.spawned[-1]

    def spawn_heartbeat(self, path):
        self.heartbeat_path = path
        self.spawned.append(FakeChild())
        return self.spawned[-1]

    def spawn_lab(self, label):
        self.spawned.append(FakeChild())
        return self.spawned[-1]


def state(hold=False, flag=False, wanted=None, agents=(), holds=(), on=True, helper="enabled", jobs_on=False, **more):
    """A state of the app as `.state.json` has it."""
    return dict({
        "v": 1, "on": on, "mode": "agentWorking", "entitlement": "licensed",
        "decision": {"hold": hold, "headline": "working" if hold else "noAgents", "stop": not on, "assertion": hold},
        "flag": {"wanted": flag if wanted is None else wanted, "helper": helper, "setup": "ready", "set": flag},
        "gate": "open", "agents": [dict(row) for row in agents], "holds": [{"id": hold_id, "kind": "timed"} for hold_id in holds],
        "jobs": {"on": jobs_on, "status": "off", "holds": [], "history": []}, "notices": [],
    }, **more)


def output():
    return io.StringIO()
