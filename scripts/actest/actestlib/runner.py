"""One run of one test: the steps one at a time, a sample every second,
the cleanup, the verdict."""
import os
import signal
import sys

from . import cleanup, expr, files, heartbeat, judge, parse, sampler, store

VERSION = 1
HINTS = {
    "until": "The runner sees this by itself.   [s] skip the test   [Control-C] stop",
    "key": "[Enter] done   [s] skip the test   [Control-C] stop",
    "ask": "[y] yes   [n] no   [s] skip the test   [Control-C] stop",
}


class Session:
    def __init__(self, test, env, ui, run_dir):
        self.test, self.env, self.ui, self.run_dir = test, env, ui, run_dir
        self.timeline = store.Timeline(run_dir)
        self.steps, self.keys, self.commands, self.children = [], {}, {}, {}
        self.names = {"run": run_dir}
        self.holds_before = sampler.holds(env)
        self.heartbeat = self.lab = None
        self.problem = None
        self.number = 0
        self.start = self.end = env.now()

    def sample(self, test=None, step=None):
        """`step` is -1 for a sample of the cleanup. The rules do not
        look at those."""
        found = sampler.take(self.env, test or self.test, self.run_dir, self.number if step is None else step, self.children)
        self.timeline.add(found)
        if found.get("app_pid") is not None:
            self.names["app_pid"] = found["app_pid"]
        return found

    def note_active(self):
        procs = {name: child.pid for name, child in self.children.items()}
        for name in ("heartbeat", "lab"):
            if getattr(self, name):
                procs[name] = getattr(self, name).pid
        store.set_active({"pid": os.getpid(), "test": self.test["id"], "run": self.run_dir, "holds_before": self.holds_before, "procs": procs})

    # MARK: Steps

    def _act(self, step):
        """What the runner does itself at the start of a step."""
        env = self.env
        if "write" in step:
            self.names.update(files.write_job(self.run_dir, step.get("in_minutes", 5), env.now()))
        if "run" in step:
            code, out = env.tool([files.render(part, self.names) for part in step["run"][1:]])
            self.commands[step["name"]] = {"code": code, "out": out[:500]}
        if "spawn" in step:
            self.children[step["name"]] = env.spawn_tool([files.render(part, self.names) for part in step["spawn"][1:]])
            self.names["pid_" + step["name"]] = self.children[step["name"]].pid
            self.note_active()
        if "signal" in step and step["name"] in self.children:
            self.children[step["name"]].send_signal(getattr(signal, "SIG" + step["signal"]))

    def _step(self, number, step):
        env, ui = self.env, self.ui
        self.number = number
        start = env.now()
        record = {"n": number, "start": start}
        self.steps.append(record)
        self._act(step)
        kind = next((name for name in ("until", "key", "ask") if name in step), None)
        ui.page(f"{self.test['id']}   step {number} of {len(self.test['steps'])}")
        ui.line(files.render(step["say"], self.names))
        if "command" in step:
            ui.line()
            ui.line("Run this in another Terminal:")
            ui.line("    " + files.render(step["command"], self.names))
        if "ask" in step:
            ui.line()
            ui.line(step["ask"])
        ui.line()
        if kind:
            ui.line(HINTS[kind])
        while True:
            tick = env.now()
            found = self.sample()
            if kind is None:
                record["how"] = "done"
                break
            waited = env.now() - start
            if kind == "until":
                if expr.holds(step["until"], found, start):
                    record["how"] = "seen"
                    break
                if waited > step["timeout"]:
                    said = f"step {number} timed out after {step['timeout']} s: {expr.reading(step['until'], found, start)}"
                    if step.get("optional"):
                        record["how"] = "timed out"
                        break
                    self.problem = said
                    return False
                ui.status(f"waiting {waited:.0f} s   {expr.reading(step['until'], found, start)}")
            else:
                ui.status(f"waiting {waited:.0f} s")
            key = env.key(max(0.0, 1.0 - (env.now() - tick)))
            if key == "s":
                self.problem = f"the owner skipped step {number}"
                return False
            if kind == "key" and key == "enter":
                record["how"] = "key"
                break
            if kind == "ask" and key in ("y", "n"):
                self.keys[step["name"]] = "yes" if key == "y" else "no"
                record["how"] = "key"
                break
        record["end"] = env.now()
        return True

    # MARK: The run

    def run(self):
        env = self.env
        aborted = False
        env.open_keys()
        try:
            if self.test["heartbeat"]:
                self.heartbeat = env.spawn_heartbeat(os.path.join(self.run_dir, "heartbeat.txt"))
            if self.test["lab"]:
                self.lab = env.spawn_lab("actest-" + self.test["id"])
            self.note_active()
            self.start = env.now()
            for number, step in enumerate(self.test["steps"], 1):
                if not self._step(number, step):
                    break
        except KeyboardInterrupt:
            aborted = True
        self.end = env.now()
        try:
            left = cleanup.run(self)
        finally:
            env.close_keys()
        return self._finish(aborted, left)

    def _finish(self, aborted, left):
        env, test = self.env, self.test
        last = self.timeline.samples[-1]["t"] if self.timeline.samples else self.end
        text = env.command(("pmset", "-g", "log"), timeout=90)[1]
        log = parse.power_log(text, self.start - 5, last + 5) if text.strip() else None
        if log is not None:
            store.write_log(self.run_dir, log)
        if self.lab:
            store.keep_lab(self.run_dir, "actest-" + test["id"])
        evidence = {
            "start": self.start, "end": self.end, "steps": self.steps, "keys": self.keys,
            "samples": [sample for sample in self.timeline.samples if sample["step"] >= 0],
            "commands": self.commands, "heartbeat": heartbeat.read(os.path.join(self.run_dir, "heartbeat.txt")), "log": log,
        }
        results = judge.judge(evidence, test["checks"])
        result, reason = judge.verdict(results, self.problem)
        if aborted:
            result, reason = "aborted", f"stopped at step {self.number}"
        build = sampler.installed_build(env)
        common = {"test": test["id"], "title": test["title"], "area": test["area"], "layer": test["layer"], "build": build,
                  "started": self.start, "ended": last, "run": os.path.basename(self.run_dir)}
        store.write_run(self.run_dir, dict(common, **{
            "runner": VERSION, "python": sys.version.split()[0], "machine": env.command(("sysctl", "-n", "hw.model"))[1].strip(),
            "macos": env.command(("sw_vers", "-productVersion"))[1].strip(), "steps": self.steps, "keys": self.keys,
            "commands": self.commands, "last_step_ended": self.end,
        }))
        verdict = dict(common, result=result, reason=reason, checks=results, cleanup=left)
        store.write_verdict(self.run_dir, verdict)
        self.ui.banner(result, test["id"], reason)
        for result_line in results:
            word = "note" if result_line["info"] else ("pass" if result_line["ok"] else "fail")
            self.ui.item({"status": word, "name": "", "text": f"{result_line['check']}  ({result_line['measured']})"})
        for tell in left["left"]:
            self.ui.line(f"Still to do: {tell}")
        self.ui.line(f"Evidence: {self.run_dir}")
        return verdict


def run_test(test, env, ui):
    """Runs one test whose preflight passed. Returns its verdict."""
    return Session(test, env, ui, store.new_run(test["id"], env.now())).run()
