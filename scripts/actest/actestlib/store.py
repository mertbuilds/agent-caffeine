"""The evidence of the runs, in the runner's own folder:

    runs/<date>-<id>-<n>/run.json        the test, the build, the Mac, the step times, the answers
    runs/<date>-<id>-<n>/timeline.jsonl  one line per second with the watches
    runs/<date>-<id>-<n>/heartbeat.txt   the time stamps of the heartbeat writer
    runs/<date>-<id>-<n>/pmset-log.txt   the power log cut to the window of the test
    runs/<date>-<id>-<n>/verdict.json    pass or fail per rule, with the measured value
    active.json                          the run that is under way, for `actest abort`
"""
import json
import os
import shutil
import time

from . import config


def _write(path, value):
    """Whole and renamed, so a reader never sees half a file."""
    draft = f"{path}.draft-{os.getpid()}"
    with open(draft, "w", encoding="utf-8") as file:
        json.dump(value, file, indent=1, sort_keys=True)
        file.write("\n")
    os.replace(draft, path)


def read_json(path):
    try:
        with open(path, encoding="utf-8") as file:
            return json.load(file)
    except (OSError, ValueError):
        return None


def new_run(test_id, now):
    """A new folder for one run. The number counts the runs of the test
    on that day."""
    day = time.strftime("%Y-%m-%d", time.localtime(now))
    os.makedirs(config.runs_dir(), mode=0o700, exist_ok=True)
    number = 1
    while True:
        path = os.path.join(config.runs_dir(), f"{day}-{test_id}-{number}")
        try:
            os.mkdir(path, 0o700)
            return path
        except FileExistsError:
            number += 1


class Timeline:
    """Appends one line per sample, so a run that is cut off keeps what
    it saw."""

    def __init__(self, run_dir):
        self.path = os.path.join(run_dir, "timeline.jsonl")
        self.samples = []

    def add(self, sample):
        self.samples.append(sample)
        with open(self.path, "a", encoding="utf-8") as file:
            file.write(json.dumps(sample, sort_keys=True, separators=(",", ":")) + "\n")


def read_timeline(run_dir):
    """The samples of a run. A last line that a kill cut off is left out."""
    samples = []
    try:
        with open(os.path.join(run_dir, "timeline.jsonl"), encoding="utf-8") as file:
            for line in file:
                try:
                    samples.append(json.loads(line))
                except ValueError:
                    continue
    except OSError:
        pass
    return samples


def write_run(run_dir, value):
    _write(os.path.join(run_dir, "run.json"), value)


def write_verdict(run_dir, value):
    _write(os.path.join(run_dir, "verdict.json"), value)


def write_log(run_dir, lines):
    with open(os.path.join(run_dir, "pmset-log.txt"), "w", encoding="utf-8") as file:
        for line in lines:
            stamp = time.strftime("%Y-%m-%d %H:%M:%S %z", time.localtime(line["t"]))
            file.write(f"{stamp} {line['kind']:<14}\t{line['text']}\n")


def keep_lab(run_dir, label):
    """Copies the lab recording of the run next to its other evidence."""
    folder = os.path.join(config.app_support(), "lab")
    try:
        names = sorted(name for name in os.listdir(folder) if label in name and name.endswith(".jsonl"))
    except OSError:
        return None
    if not names:
        return None
    shutil.copyfile(os.path.join(folder, names[-1]), os.path.join(run_dir, "lab.jsonl"))
    return names[-1]


def set_active(value):
    os.makedirs(config.evidence_root(), mode=0o700, exist_ok=True)
    _write(config.active_file(), value)


def clear_active():
    try:
        os.unlink(config.active_file())
    except OSError:
        pass


def active():
    return read_json(config.active_file())


def verdicts():
    """Every verdict there is, the oldest first."""
    found = []
    try:
        names = sorted(os.listdir(config.runs_dir()))
    except OSError:
        return found
    for name in names:
        verdict = read_json(os.path.join(config.runs_dir(), name, "verdict.json"))
        if verdict:
            found.append(dict(verdict, run=name))
    found.sort(key=lambda verdict: verdict.get("ended", 0))
    return found


def find_run(run_id):
    """The folder of a run, by its name or by the end of its name."""
    try:
        names = sorted(os.listdir(config.runs_dir()))
    except OSError:
        return None
    matches = [name for name in names if name == run_id] or [name for name in names if name.endswith(run_id) or run_id in name]
    return os.path.join(config.runs_dir(), matches[-1]) if matches else None
