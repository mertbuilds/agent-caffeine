"""Where things are. Every path the runner reads or writes is named here."""
import os
import re

BUNDLE_ID = "com.caffeinagent.app"
SWITCH_KEY = "StateForTests"
SWITCH_ON = f"defaults write {BUNDLE_ID} {SWITCH_KEY} -bool true"
# The time limit of the closed lid limit in seconds. Only the owner sets
# and deletes it, and only the test below has a step for it.
LIMIT_KEY = "ClosedLidLimitSecondsForTests"
LIMIT_OFF = f"defaults delete {BUNDLE_ID} {LIMIT_KEY}"
LIMIT_TEST = "HOLD-30"
# The time of the offline rule in seconds, by the same rules.
OFFLINE_LIMIT_KEY = "OfflineLimitSecondsForTests"
OFFLINE_LIMIT_TEST = "HOLD-40"
# Each hidden limit with the one test that may start while it is set.
LIMITS = {LIMIT_KEY: LIMIT_TEST, OFFLINE_LIMIT_KEY: OFFLINE_LIMIT_TEST}


def limit_off(key):
    return f"defaults delete {BUNDLE_ID} {key}"
WAKE_OWNER = "com.caffeinagent.app.wake"
APP_NAMES = ("Agent Caffeine.app", "agent caffeine.app")
APP_BINARY = "Contents/MacOS/caffeinagent"
TOOL_BINARY = "Contents/MacOS/agent-caffeine"
# A state file older than this says nothing: the app rewrites it every 4 s.
STATE_MAX_AGE = 12.0
MIN_FREE_BYTES = 1 << 30

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(os.path.dirname(HERE))
TESTS_DIR = os.path.join(HERE, "tests")


def home():
    return os.path.expanduser("~")


def app_support():
    """The folder of the app. The runner only reads here."""
    return os.path.join(home(), "Library/Application Support", BUNDLE_ID)


def state_file():
    return os.path.join(app_support(), ".state.json")


def status_file():
    return os.path.join(app_support(), ".status")


def claude_sessions_dir():
    """Where Claude Code keeps one file per session. The runner reads
    `pid`, `kind`, `status` and `statusUpdatedAt` there and nothing else."""
    return os.path.join(home(), ".claude/sessions")


def evidence_root():
    """The folder of the runner. Never inside the folder of the app."""
    return os.environ.get("ACTEST_HOME") or os.path.join(home(), "Library/Application Support/Agent Caffeine Tests")


def runs_dir():
    return os.path.join(evidence_root(), "runs")


def active_file():
    return os.path.join(evidence_root(), "active.json")


def installed_app():
    """The install in the Applications folder, by the name it has on disk."""
    try:
        names = os.listdir("/Applications")
    except OSError:
        return None
    for name in names:
        if name.lower() == APP_NAMES[0].lower():
            return os.path.join("/Applications", name)
    return None


def expected_build():
    """Version and build of this checkout, from project.yml."""
    try:
        with open(os.path.join(REPO, "project.yml"), encoding="utf-8") as file:
            text = file.read()
    except OSError:
        return None
    version = re.search(r'MARKETING_VERSION:\s*"?([^"\s]+)"?', text)
    build = re.search(r'CURRENT_PROJECT_VERSION:\s*"?([^"\s]+)"?', text)
    if not version or not build:
        return None
    return f"{version.group(1)} ({build.group(1)})"
