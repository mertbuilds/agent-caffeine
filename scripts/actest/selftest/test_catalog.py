import os
import plistlib
import shutil
import tempfile
import time
import unittest

from actestlib import catalog, config, files, judge

GOOD = {
    "id": "HELP-03", "title": "t", "layer": 1, "area": "help", "minutes": 3,
    "steps": [{"say": "Kill it.", "command": "kill -9 {app_pid}", "until": "app.running=false"}, {"say": "Hear?", "ask": "Chime?", "name": "chime"}],
    "checks": ["within 65s after step 1: sleepdisabled=0", "key chime is yes"],
}


def test(**changes):
    return dict({key: (list(map(dict, value)) if key == "steps" else value) for key, value in GOOD.items()}, **changes)


class CatalogTests(unittest.TestCase):
    def test_every_test_file_loads(self):
        tests = catalog.load_all()
        self.assertGreaterEqual(len(tests), 40)
        for found in tests.values():
            self.assertEqual(found["layer"], 1, found["id"])
            self.assertGreater(found["minutes"], 0)
            self.assertTrue(found["why"], found["id"])
        for safety in ("HELP-21", "HELP-02", "HELP-03", "HOLD-04", "HOLD-30", "HOLD-31", "LID-20", "LID-08", "DET-GEN-01", "WAKE-E01", "WAKE-E06", "CLI-10"):
            self.assertIn(safety, tests)
        self.assertTrue(all(tests[name].get("decides") for name in ("WAKE-E01", "WAKE-E03")))

    def test_the_test_files_tell_the_owner_nothing_the_runner_may_not_do(self):
        for folder, _, names in os.walk(config.TESTS_DIR):
            for name in names:
                with open(os.path.join(folder, name), encoding="utf-8") as file:
                    text = file.read()
                self.assertNotIn(chr(8212), text, name)
                self.assertNotIn("cancelall", text, name)
        for found in catalog.load_all().values():
            for step in found["steps"]:
                for key in ("run", "spawn"):
                    self.assertEqual(step.get(key, ["agent-caffeine"])[0], "agent-caffeine")
                if "sudo" in step.get("command", "") or "kill" in step.get("command", ""):
                    self.assertNotIn("run", step, "The owner runs it, not the runner")

    def test_defaults_are_filled_in(self):
        found = catalog.validate(test())
        self.assertEqual(found["steps"][0]["timeout"], catalog.DEFAULT_TIMEOUT)
        self.assertEqual((found["every"], found["heartbeat"], found["lab"], found["watch"], found["cleanup"]), (1, False, False, [], []))

    def test_what_is_wrong_is_said(self):
        wrong = [
            (test(id="help3"), "is not like HELP-03"),
            (test(extra=1), "unknown key extra"),
            (test(watch=["claude", "mail"]), "watch is of claude, sched, not mail"),
            (test(checks=["within 65s after step 5: sleepdisabled=0"]), "there is no step 5"),
            (test(checks=["key glow is yes"]), "no step has the name glow"),
            (test(checks=["sometimes: lid=open"]), "cannot read the rule"),
            (test(steps=[{"say": "x", "until": "lid closed"}]), "cannot read the condition"),
            (test(steps=[{"say": "x", "run": ["sudo", "pmset"], "name": "x"}]), "run starts agent-caffeine and nothing else"),
            (test(steps=[{"say": "x", "until": "lid=open", "key": "enter"}]), "one of until, key and ask"),
            (test(steps=[{"say": "x", "ask": "Yes?"}]), "needs a name"),
            (test(steps=[{"say": "x", "until": "probe.none=true"}], checks=[]), "there is no probe none"),
            (test(needs={"power": "solar"}), "power is any, ac or battery"),
            (test(probes={"x": {"kind": "exists", "path": "~/.ssh/id_rsa"}}), "not one of our own files"),
            (test(cleanup=[{"expect": "power=ac"}]), "expect and tell"),
            (test(checks=["at end: held.chime=true"]), "no run step has the name chime"),
            (test(checks=["if idle: sometimes"]), "cannot read the rule"),
            (test(needs={"quiet": True}), "unknown key quiet"),
        ]
        for bad, said in wrong:
            with self.assertRaises(catalog.TestError) as raised:
                catalog.validate(bad)
            self.assertIn(said, str(raised.exception))

    def test_each_test_says_when_it_can_start(self):
        tests = catalog.load_all()
        by_kind = {}
        for found in tests.values():
            by_kind.setdefault(catalog.when(found), set()).add(found["id"])
        self.assertEqual(by_kind["needs idle"], {"CLI-10", "DET-GEN-01", "HELP-02", "WAKE-18", "WAKE-E03", "WAKE-E04", "WAKE-E05", "WAKE-E06"})
        self.assertEqual(by_kind["needs sleep"], {"WAKE-E01", "WAKE-E02"})
        self.assertEqual(len(by_kind["any time"]), len(tests) - 10)
        for name in by_kind["needs idle"]:
            self.assertIn("Needs an idle Mac", tests[name]["why"], name)
            self.assertEqual(catalog.idle_rules(tests[name]), 0, "A test for an idle Mac has no rule to skip")
        self.assertEqual({name: catalog.idle_rules(tests[name]) for name in ("CLI-01", "CLI-02", "CLI-03", "CLI-05", "HOLD-04", "CLI-07", "CLI-09", "HELP-03")},
                         {"CLI-01": 2, "CLI-02": 1, "CLI-03": 1, "CLI-05": 1, "HOLD-04": 1, "CLI-07": 0, "CLI-09": 0, "HELP-03": 0})
        for found in tests.values():
            judged = [text for text in found["checks"] if not catalog.judge.needs_idle(text) and not text.startswith("info ")]
            self.assertTrue(judged, f"{found['id']} has a rule that is judged while agents work")
        self.assertEqual(catalog.when(catalog.validate(test(needs={"sleeps": True}))), "needs sleep")
        self.assertEqual(catalog.when(catalog.validate(test())), "any time")

    def test_a_probe_reads_our_own_files_only(self):
        for path in ["~/.claude/skills/agent-caffeine/SKILL.md", "~/.agents/skills/agent-caffeine/SKILL.md", "~/.local/bin/agent-caffeine",
                     "{run}/job.log", catalog.MARKER, f"~/Library/LaunchAgents/{catalog.JOB_LABEL}.plist"]:
            self.assertTrue(catalog.probe_path_allowed(path), path)
        for path in ["~/.claude/settings.json", "~/.claude/skills/other/SKILL.md", "/etc/passwd", "{run}/../x", "~/../x/skills/agent-caffeine/SKILL.md",
                     "~/Library/LaunchAgents/other.plist", "~/.claude/sessions/1.json"]:
            self.assertFalse(catalog.probe_path_allowed(path), path)


class FilesTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp(prefix="actest-selftest-")

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def test_the_test_job_is_harmless_and_runs_on_a_full_minute(self):
        now = 1_791_200_030
        names = files.write_job(self.folder, 5, now, seconds=600)
        self.assertEqual(names["job_time"] % 60, 0)
        self.assertTrue(300 < names["job_time"] - now <= 360)
        with open(names["job_plist"], "rb") as file:
            plist = plistlib.load(file)
        self.assertEqual(plist["Label"], catalog.JOB_LABEL)
        local = time.localtime(names["job_time"])
        self.assertEqual(plist["StartCalendarInterval"], {"Hour": local.tm_hour, "Minute": local.tm_min})
        script = plist["ProgramArguments"][2]
        self.assertIn(os.path.join(self.folder, "job.log"), script)
        self.assertIn("-lt 60", script)
        for word in ("sudo", "pmset", "curl", "rm ", "http"):
            self.assertNotIn(word, script)
        self.assertNotIn("KeepAlive", plist)

    def test_texts_get_their_times(self):
        base = time.mktime((2026, 10, 10, 15, 0, 20, 0, 0, -1))
        names = dict(files.alarm(4, base), job_time=base + 600, app_pid=77, run="/r")
        self.assertEqual(names["alarm_date"], "10/10/26 15:05:00")
        self.assertEqual(files.render("kill -9 {app_pid} in {run}", names), "kill -9 77 in /r")
        self.assertEqual(files.render("at {alarm_hhmm}, open at {alarm_hhmm+2}", names), "at 15:05, open at 15:07")
        self.assertEqual(files.render("job {job_hhmm+3}, now {clock+17}", names, base), "job 15:13, now 15:17")
        self.assertEqual(files.render('wake "{alarm_date}"', names), 'wake "10/10/26 15:05:00"')
        self.assertEqual(files.render("{job_hhmm}", {}), "{job_hhmm}")

    def test_the_alarm_is_a_moment_and_the_log_knows_finer_kinds(self):
        evidence = {"start": 0, "end": 400, "alarm": 240, "steps": [], "samples": [], "log": [
            {"t": 100, "kind": "Sleep", "text": "Entering Sleep state due to 'Clamshell Sleep'"},
            {"t": 180, "kind": "DarkWake", "text": "DarkWake from Deep Idle [CDNP] : due to SMC.OutboxNotEmpty"},
            {"t": 241, "kind": "DarkWake", "text": "DarkWake from Deep Idle [CDNP] : due to RTC/Alarm Using BATT"},
            {"t": 250, "kind": "Notification", "text": "Display is turned off"},
        ]}
        results = judge.judge(evidence, ["log within 20s after alarm - 5s has AlarmWake", "log from start to alarm - 10s has no AlarmWake",
                                         "log from start to end has DisplayOff", "log from start to end has no DisplayOn",
                                         "log from start to alarm - 10s has Sleep"])
        self.assertEqual([result["ok"] for result in results], [True] * 5)
        self.assertEqual(results[0]["measured"], "1 line of AlarmWake, first after 6 s")
        evidence["alarm"] = None
        self.assertEqual(judge.judge(evidence, ["log within 20s after alarm has AlarmWake"])[0]["measured"], "the run did not reach this step")


if __name__ == "__main__":
    unittest.main()
