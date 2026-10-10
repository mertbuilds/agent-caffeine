"""Files a test puts into the folder of its run for the owner to use. The
runner loads nothing itself: a step tells the owner the command."""
import os
import plistlib
import re
import time

from .catalog import JOB_LABEL


def write_job(run_dir, in_minutes, now, seconds=20):
    """A harmless launchd job: from its time on it appends one line to
    job.log in the folder of the run every 10 seconds, for `seconds`, so
    the app can see it run. It reaches no network and no other file.
    Returns the names a step text can use."""
    fire = (int(now) // 60 + 1 + int(in_minutes)) * 60
    local = time.localtime(fire)
    log = os.path.join(run_dir, "job.log")
    script = f'i=0; while [ $i -lt {max(1, int(seconds) // 10)} ]; do date "+%s ran" >> "{log}"; sleep 10; i=$((i+1)); done'
    plist = {
        "Label": JOB_LABEL,
        "ProgramArguments": ["/bin/sh", "-c", script],
        "StartCalendarInterval": {"Hour": local.tm_hour, "Minute": local.tm_min},
    }
    path = os.path.join(run_dir, JOB_LABEL + ".plist")
    with open(path, "wb") as file:
        plistlib.dump(plist, file)
    return {"job_time": fire, "job_plist": path, "job_label": JOB_LABEL}


def alarm(in_minutes, now):
    """The time of an alarm the owner sets by hand, on a full minute, and
    the date as `pmset schedule` reads it."""
    at = (int(now) // 60 + 1 + int(in_minutes)) * 60
    return {"alarm_time": at, "alarm_date": time.strftime("%m/%d/%y %H:%M:%S", time.localtime(at))}


def render(text, names, now=None):
    """Fills `{name}` in a step text. `{job_hhmm+3}` is the time of the
    job plus 3 minutes, as the clock shows it. `{clock+5}` is the time
    in 5 minutes."""
    def clock(match):
        base = now if match.group(1) == "clock" else names.get(match.group(1) + "_time")
        if base is None:
            return match.group(0)
        return time.strftime("%H:%M", time.localtime(base + 60 * int(match.group(2) or 0)))

    text = re.sub(r"\{(clock|job|alarm)(?:_hhmm)?(?:\+(\d+))?\}", clock, text)
    for name, value in names.items():
        text = text.replace("{" + name + "}", str(value))
    return text
