"""Files a test puts into the folder of its run for the owner to use. The
runner loads nothing itself: a step tells the owner the command."""
import os
import plistlib
import re
import time

from .catalog import JOB_LABEL


def write_job(run_dir, in_minutes, now):
    """A harmless launchd job: at its time it appends one line to
    job.log in the folder of the run, and sleeps 20 seconds so the app
    can see it run. Returns the names a step text can use."""
    fire = (int(now) // 60 + 1 + int(in_minutes)) * 60
    local = time.localtime(fire)
    log = os.path.join(run_dir, "job.log")
    plist = {
        "Label": JOB_LABEL,
        "ProgramArguments": ["/bin/sh", "-c", f'date "+%s ran" >> "{log}"; sleep 20'],
        "StartCalendarInterval": {"Hour": local.tm_hour, "Minute": local.tm_min},
    }
    path = os.path.join(run_dir, JOB_LABEL + ".plist")
    with open(path, "wb") as file:
        plistlib.dump(plist, file)
    return {"job_time": fire, "job_plist": path, "job_label": JOB_LABEL}


def render(text, names):
    """Fills `{name}` in a step text. `{job_hhmm+3}` is the time of the
    job plus 3 minutes, as the clock shows it."""
    def clock(match):
        if "job_time" not in names:
            return match.group(0)
        return time.strftime("%H:%M", time.localtime(names["job_time"] + 60 * int(match.group(1) or 0)))

    text = re.sub(r"\{job_hhmm(?:\+(\d+))?\}", clock, text)
    for name, value in names.items():
        text = text.replace("{" + name + "}", str(value))
    return text
