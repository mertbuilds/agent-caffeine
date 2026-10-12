"""What the runner reaches the Mac through. Everything here only reads,
but for the command line tool of Agent Caffeine, the heartbeat writer and
the files in the runner's own folder. A self-test passes a fake of this.

The runner never uses sudo, never writes a power setting, never schedules
a power event and never ends the app or its helper. `command` refuses
what is not on the list below.
"""
import os
import select
import subprocess
import sys
import termios
import time
import tty

from . import config

READ_ONLY = {
    ("pmset", "-g"), ("pmset", "-g", "batt"), ("pmset", "-g", "assertions"), ("pmset", "-g", "sched"), ("pmset", "-g", "log"),
    ("ioreg", "-r", "-k", "AppleClamshellState", "-d", "4"), ("ps", "-axo", "pid=,comm="),
    ("defaults", "read", config.BUNDLE_ID, config.SWITCH_KEY), ("defaults", "read", config.BUNDLE_ID, config.LIMIT_KEY),
    ("defaults", "read", config.BUNDLE_ID, config.OFFLINE_LIMIT_KEY),
    ("system_profiler", "SPDisplaysDataType", "-json"),
    ("sw_vers", "-productVersion"), ("sysctl", "-n", "hw.model"),
}


class Refused(RuntimeError):
    pass


class RealEnv:
    def __init__(self):
        self.app = config.installed_app()
        self.tool_path = os.path.join(self.app, config.TOOL_BINARY) if self.app else None
        self._terminal = None

    # MARK: Time

    def now(self):
        return time.time()

    def sleep(self, seconds):
        time.sleep(max(0.0, seconds))

    # MARK: Reads

    def command(self, args, timeout=20):
        """(exit code, stdout) of a tool that only reads."""
        if tuple(args) not in READ_ONLY:
            raise Refused(f"the runner does not run: {' '.join(args)}")
        try:
            done = subprocess.run(list(args), capture_output=True, text=True, timeout=timeout, check=False)
        except (OSError, subprocess.TimeoutExpired):
            return 1, ""
        return done.returncode, done.stdout

    def read(self, path, limit=1 << 20):
        try:
            with open(os.path.expanduser(path), "rb") as file:
                return file.read(limit)
        except OSError:
            return None

    def exists(self, path):
        return os.path.lexists(os.path.expanduser(path))

    def names(self, path):
        """The names in a folder. Empty when it cannot be listed."""
        try:
            return sorted(os.listdir(os.path.expanduser(path)))
        except OSError:
            return []

    def link_target(self, path):
        try:
            return os.readlink(os.path.expanduser(path))
        except OSError:
            return None

    def free_bytes(self):
        stats = os.statvfs(config.home())
        return stats.f_bavail * stats.f_frsize

    # MARK: The command line tool

    def tool(self, args, timeout=30):
        """(exit code, stdout and stderr) of agent-caffeine. None when the
        app is not installed."""
        if not self.tool_path:
            return None
        try:
            done = subprocess.run([self.tool_path] + list(args), capture_output=True, text=True, timeout=timeout, check=False)
        except (OSError, subprocess.TimeoutExpired):
            return 1, ""
        return done.returncode, done.stdout + done.stderr

    def spawn_tool(self, args):
        """agent-caffeine in the background, in a group of its own so
        Control-C in the runner does not reach it."""
        return subprocess.Popen(
            [self.tool_path] + list(args), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

    def spawn_heartbeat(self, path):
        return subprocess.Popen(
            [sys.executable, "-m", "actestlib.heartbeat", path], cwd=config.HERE, stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
        )

    def spawn_lab(self, label):
        """A lab recording with the binary of the installed app. It
        starts no menu bar app and takes no power assertion."""
        if not self.app:
            return None
        return subprocess.Popen(
            [os.path.join(self.app, config.APP_BINARY), "--lab-record", label], stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
        )

    # MARK: Keys

    def open_keys(self):
        """One key at a time, with no Enter. A pipe stays as it is."""
        if self._terminal is None and sys.stdin.isatty():
            self._terminal = termios.tcgetattr(sys.stdin.fileno())
            tty.setcbreak(sys.stdin.fileno())

    def close_keys(self):
        if self._terminal is not None:
            termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, self._terminal)
            self._terminal = None

    def key(self, timeout):
        """The key the owner pressed within `timeout` seconds, or None."""
        try:
            ready, _, _ = select.select([sys.stdin], [], [], max(0.0, timeout))
        except (OSError, ValueError):
            self.sleep(timeout)
            return None
        if not ready:
            return None
        # Past the buffer of Python, so a second key is not left in it.
        char = os.read(sys.stdin.fileno(), 1).decode("utf-8", "ignore")
        if char == "":
            self.sleep(timeout)
            return None
        return "enter" if char in "\r\n" else char.lower()
