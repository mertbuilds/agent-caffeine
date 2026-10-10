import unittest

from actestlib import config, preflight
from selftest import fakes


def items(env, test=None):
    found = preflight.check(preflight.gather(env), test)
    return {item["name"]: item for item in found}


class PreflightTests(unittest.TestCase):
    def setUp(self):
        self.expected = config.expected_build()

    def test_a_ready_mac_passes_every_item(self):
        env = fakes.FakeEnv(lambda t: {"state": fakes.state()}, build=self.expected)
        found = items(env)
        self.assertEqual([name for name, item in found.items() if item["status"] in ("fail", "unknown")], [])
        self.assertEqual(found["flag"]["text"], "SleepDisabled is 0, the app wants 0")
        self.assertEqual(found["timers"]["status"], "note")

    def test_the_installed_build_without_the_export_is_said_plainly(self):
        env = fakes.FakeEnv(lambda t: {"awake": True, "flag": 1}, export=False, switch=False, build=self.expected)
        found = items(env)
        self.assertEqual(found["export"]["status"], "fail")
        self.assertEqual(found["export"]["text"], "installed build has no state export: install the new build")
        self.assertEqual(found["switch"]["fix"], "Run: defaults write com.caffeinagent.app StateForTests -bool true")
        self.assertEqual(found["helper"]["status"], "unknown")
        self.assertEqual(found["flag"]["status"], "pass", "The flag is 1 and the app holds")
        self.assertEqual(found["on"]["status"], "pass")
        self.assertNotIn("state", found)

    def test_a_flag_that_nothing_holds_stops_the_session(self):
        env = fakes.FakeEnv(lambda t: {"flag": 1, "state": fakes.state()}, build=self.expected)
        self.assertEqual(items(env)["flag"]["status"], "fail")
        env = fakes.FakeEnv(lambda t: {"flag": 1, "awake": False}, export=False, build=self.expected)
        self.assertEqual(items(env)["flag"]["status"], "fail")
        env = fakes.FakeEnv(lambda t: {"flag": 0, "state": fakes.state(hold=True, flag=False, wanted=True)}, build=self.expected)
        self.assertEqual(items(env)["flag"]["text"], "SleepDisabled is 0, the app wants 1")

    def test_each_failing_item_has_one_fix(self):
        world = {
            "pid": None, "lid": "closed", "power": "ac", "charge": 20, "sched": ["pmset"], "displays": 1,
        }
        env = fakes.FakeEnv(lambda t: world, build="1.0.2 (16)")
        env.holds = ["0a1b2c3d"]
        env.free = 1000
        env.files[config.active_file()] = b"{}"
        test = {"needs": {"power": "battery", "charge": 40, "display": "builtin", "helper": True, "agents": ["grok"], "wake_for_jobs": True}}
        found = items(env, test)
        failing = {name for name, item in found.items() if item["status"] == "fail"}
        self.assertEqual(failing, {"build", "running", "holds", "recording", "alarm", "power", "charge", "lid", "display", "disk"})
        for name in failing:
            self.assertTrue(found[name]["fix"], name)
        self.assertEqual(found["power"]["fix"], "Pull the charger.")
        self.assertEqual(found["build"]["fix"], f"Install build {self.expected}.")
        self.assertEqual({name for name, item in found.items() if item["status"] == "unknown"}, {"helper", "agent grok", "wake for jobs"})

    def test_the_needs_of_a_test_are_checked_against_the_state(self):
        rows = [{"id": "grok", "pid": 9, "state": "idle"}]
        env = fakes.FakeEnv(lambda t: {"power": "battery", "charge": 80, "state": fakes.state(agents=rows, helper="notRegistered")}, build=self.expected)
        test = {"needs": {"power": "battery", "helper": True, "agents": ["grok", "hermes-agent"], "wake_for_jobs": True}}
        found = items(env, test)
        self.assertEqual(found["agent grok"]["status"], "pass")
        self.assertEqual(found["agent hermes-agent"]["status"], "fail")
        self.assertEqual(found["helper"]["status"], "fail")
        self.assertEqual(found["wake for jobs"]["status"], "fail")
        self.assertEqual(found["power"]["status"], "pass")
        self.assertEqual(len(preflight.blocked(list(found.values()))), 3)

    def test_a_paused_app_and_an_ended_licence_fail(self):
        env = fakes.FakeEnv(lambda t: {"state": fakes.state(pausedUntil=1.0, entitlement="expired")}, build=self.expected)
        found = items(env)
        self.assertEqual(found["on"]["status"], "fail")
        self.assertEqual(found["licence"]["status"], "fail")

    def test_the_preflight_only_reads(self):
        env = fakes.FakeEnv(lambda t: {"state": fakes.state()})
        preflight.gather(env)
        self.assertTrue(all(args[0] in ("pmset", "ioreg", "ps", "defaults", "system_profiler") for args in env.commands))
        self.assertTrue(all(args[:2] != ("defaults", "write") and "-a" not in args for args in env.commands))
        self.assertEqual(env.tool_calls, [["status", "--json"]])


if __name__ == "__main__":
    unittest.main()
