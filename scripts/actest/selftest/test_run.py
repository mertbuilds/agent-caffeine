import io
import json
import os
import shutil
import tempfile
import unittest

from actestlib import catalog, config, runner, store, ui
from selftest import fakes

LID = {
    "id": "HOLD-04", "title": "Lid closed on battery", "layer": 1, "area": "hold", "minutes": 2, "heartbeat": True,
    "needs": {"power": "any", "helper": True},
    "steps": [
        {"say": "The runner starts a hold.", "run": ["agent-caffeine", "hold", "--for", "12m", "--json"], "name": "hold",
         "until": "app.hold=true and sleepdisabled=1", "timeout": 20},
        {"say": "Pull the charger.", "until": "power=battery", "timeout": 60},
        {"say": "Close the lid.", "until": "lid=closed", "timeout": 60},
        {"say": "Listen.", "ask": "Did you hear the chime?", "name": "chime"},
        {"say": "Leave the lid closed.", "until": "time>=60s"},
        {"say": "Open the lid.", "until": "lid=open", "timeout": 60},
    ],
    "checks": [
        "exit hold == 0",
        "heartbeat gap from step 3 to step 6 < 15s",
        "always from step 3 to step 6: sleepdisabled=1 and app.hold=true",
        "log from step 3 to step 6 has no Sleep,DarkWake",
        "key chime is yes",
    ],
    "cleanup": [{"expect": "power=ac", "tell": "Plug the charger in again."}],
}

AGENT = {
    "id": "DET-GROK-02", "title": "Grok: quiet command", "layer": 1, "area": "det", "minutes": 4, "needs": {"agents": ["grok"]},
    "steps": [
        {"say": "Send the prompt to Grok.", "key": "enter"},
        {"say": "Wait for the answer.", "key": "enter"},
        {"say": "Wait.", "until": "time>=15s"},
    ],
    "checks": [
        "within 10s after step 1: app.agent[grok].state=working",
        "always from step 1 + 10s to step 2 - 5s: app.agent[grok].state=working",
        "within 10s after step 2: app.agent[grok].state=idle",
    ],
}


class RunTests(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp(prefix="actest-selftest-")
        os.environ["ACTEST_HOME"] = self.home
        self.out = io.StringIO()
        self.ui = ui.UI(plain=True, out=self.out)

    def tearDown(self):
        del os.environ["ACTEST_HOME"]
        shutil.rmtree(self.home, ignore_errors=True)

    def lid_world(self, env):
        def world(t):
            held = bool(env.holds)
            closed = 10 <= t < 80
            return {"power": "battery" if 5 <= t < 90 else "ac", "charge": 80, "lid": "closed" if closed else "open",
                    "flag": 1 if held else 0, "awake": held, "state": fakes.state(hold=held, flag=held, holds=env.holds)}
        return world

    def run_lid(self, asleep=None, keys=None):
        env = fakes.FakeEnv(None, keys=keys or {12: "y"})
        env.world = self.lid_world(env)
        if asleep:
            env.asleep = asleep
            fakes.log_line(env, 31, "Sleep", "Entering Sleep state due to 'Clamshell Sleep'")
        fakes.log_line(env, 40, "Notification", "Display is turned off")
        fakes.log_line(env, 2, "Sleep", "Before the lid closed")
        return env, runner.run_test(catalog.validate(json.loads(json.dumps(LID))), env, self.ui)

    def test_a_lid_test_that_stays_awake_passes(self):
        env, verdict = self.run_lid()
        self.assertEqual(verdict["result"], "pass", verdict["reason"])
        self.assertEqual(verdict["reason"], "exit hold == 0 (exit code 0)")
        self.assertEqual([check["ok"] for check in verdict["checks"]], [True] * 5)
        self.assertEqual(verdict["checks"][1]["measured"], "largest gap 2 s")
        run_dir = os.path.join(config.runs_dir(), verdict["run"])
        self.assertEqual(sorted(os.listdir(run_dir)), ["heartbeat.txt", "pmset-log.txt", "run.json", "timeline.jsonl", "verdict.json"])
        run = store.read_json(os.path.join(run_dir, "run.json"))
        self.assertEqual([step["how"] for step in run["steps"]], ["seen", "seen", "seen", "key", "seen", "seen"])
        self.assertEqual(run["keys"], {"chime": "yes"})
        self.assertEqual(run["build"], "1.0.3 (17)")
        samples = store.read_timeline(run_dir)
        self.assertGreater(len(samples), 80)
        self.assertEqual(samples[20]["lid"], "closed")
        with open(os.path.join(run_dir, "timeline.jsonl"), encoding="utf-8") as file:
            self.assertNotIn("Secret", file.read())
        with open(os.path.join(run_dir, "pmset-log.txt"), encoding="utf-8") as file:
            self.assertEqual(len(file.read().splitlines()), 2, "Cut to the window of the test")
        self.assertIn("PASS   HOLD-04", self.out.getvalue())

    def test_the_cleanup_releases_the_hold_and_waits_for_the_charger(self):
        env, verdict = self.run_lid()
        self.assertEqual(env.holds, [])
        self.assertIn(["release", "aaaa0002"], env.tool_calls)
        self.assertEqual(verdict["cleanup"]["actions"], ["released the hold aaaa0002", "stopped the heartbeat"])
        self.assertEqual(verdict["cleanup"]["left"], [], "The charger was back before the wait ran out")
        self.assertIn("Plug the charger in again.", self.out.getvalue())
        self.assertIsNone(store.active())
        self.assertEqual(env.spawned[0].signals, [15])

    def test_a_mac_that_slept_fails_with_the_measured_gap(self):
        env, verdict = self.run_lid(asleep=lambda t: 30 <= t < 60)
        self.assertEqual(verdict["result"], "fail")
        self.assertEqual(verdict["reason"], "heartbeat gap from step 3 to step 6 < 15s (largest gap 32 s)")
        self.assertEqual(verdict["checks"][3]["measured"], "1 line of Sleep,DarkWake, first after 21 s")
        self.assertIn("FAIL   HOLD-04", self.out.getvalue())

    def test_no_chime_fails_the_key_rule(self):
        env, verdict = self.run_lid(keys={12: "n"})
        self.assertEqual(verdict["reason"], "key chime is yes (answer: no)")

    def test_control_c_aborts_and_still_cleans_up(self):
        env, verdict = self.run_lid(keys={12: "interrupt"})
        self.assertEqual(verdict["result"], "aborted")
        self.assertEqual(verdict["reason"], "stopped at step 4")
        self.assertEqual(env.holds, [])
        self.assertIn("Open the lid.", self.out.getvalue().splitlines())
        self.assertIsNone(store.active())

    def test_a_step_that_never_comes_times_out(self):
        env = fakes.FakeEnv(lambda t: {"state": fakes.state()})
        verdict = runner.run_test(catalog.validate(json.loads(json.dumps(LID))), env, self.ui)
        self.assertEqual(verdict["result"], "fail")
        self.assertTrue(verdict["reason"].startswith("step 1 timed out after 20 s: app.hold=false, sleepdisabled=0"))

    def agent_world(self, idle_at=None):
        def world(t):
            working = 8 <= t < 50 and not (idle_at and idle_at <= t < idle_at + 4)
            rows = [{"id": "grok", "pid": 9, "role": "session", "state": "working" if working else "idle", "why": "x", "level": "state"}]
            return {"awake": working, "state": fakes.state(hold=working, agents=rows)}
        return world

    def test_an_agent_test_passes_when_the_app_follows_the_owner(self):
        env = fakes.FakeEnv(self.agent_world(), keys={5: "enter", 50: "enter"})
        verdict = runner.run_test(catalog.validate(json.loads(json.dumps(AGENT))), env, self.ui)
        self.assertEqual(verdict["result"], "pass", verdict["reason"])
        self.assertEqual(verdict["checks"][0]["measured"], "true after 3 s")
        self.assertEqual(verdict["checks"][2]["measured"], "true after 0 s")

    def test_a_wrong_release_in_the_turn_fails(self):
        env = fakes.FakeEnv(self.agent_world(idle_at=30), keys={5: "enter", 50: "enter"})
        verdict = runner.run_test(catalog.validate(json.loads(json.dumps(AGENT))), env, self.ui)
        self.assertEqual(verdict["result"], "fail")
        self.assertIn("always from step 1 + 10s to step 2 - 5s: app.agent[grok].state=working (false after 15 s, in 4 of", verdict["reason"])

    def test_the_owner_can_skip(self):
        env = fakes.FakeEnv(self.agent_world(), keys={3: "s"})
        verdict = runner.run_test(catalog.validate(json.loads(json.dumps(AGENT))), env, self.ui)
        self.assertEqual(verdict["reason"], "the owner skipped step 1")

    def test_the_real_environment_refuses_what_is_not_a_read(self):
        from actestlib import env as environment
        real = environment.RealEnv.__new__(environment.RealEnv)
        for args in [("pmset", "-a", "disablesleep", "0"), ("pmset", "schedule", "cancelall"), ("sudo", "pmset", "-g"),
                     ("defaults", "write", config.BUNDLE_ID, config.SWITCH_KEY, "-bool", "true"), ("kill", "-9", "1"), ("osascript", "-e", "x")]:
            with self.assertRaises(environment.Refused):
                real.command(args)

    def test_the_runner_never_writes_a_power_setting(self):
        env, _ = self.run_lid()
        self.assertTrue(all(args[:2] in (("pmset", "-g"),) or args[0] in ("ioreg", "ps", "sysctl", "sw_vers") for args in env.commands), set(env.commands))
        self.assertTrue(all(call[0] in ("hold", "release", "status") for call in env.tool_calls))


if __name__ == "__main__":
    unittest.main()
