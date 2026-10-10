import unittest

from actestlib import judge


def sample(t, **fields):
    return dict({"t": t, "app": None}, **fields)


def evidence():
    """A lid test: closed at 20, opened at 80. The flag clears at 95."""
    samples = []
    for t in range(0, 121):
        closed = 20 <= t < 80
        samples.append(sample(
            t, lid="closed" if closed else "open", sleepdisabled=1 if t < 95 else 0, app_pid=7,
            app={"decision": {"hold": t < 90}, "agents": [{"id": "grok", "state": "working" if 26 <= t < 70 else "idle"}]},
        ))
    return {
        "start": 0, "end": 120, "samples": samples,
        "steps": [{"n": 1, "start": 0, "end": 10}, {"n": 2, "start": 10, "end": 20}, {"n": 3, "start": 20, "end": 80}],
        "keys": {"chime": "yes", "glow": "no"},
        "commands": {"seven": {"code": 7, "out": ""}, "refused": {"code": 1, "out": "Agent Caffeine is not running, so nothing keeps"}},
        "heartbeat": [float(t) for t in range(0, 121, 2)],
        "log": [{"t": 100, "kind": "Sleep", "text": "Entering Sleep state"}, {"t": 50, "kind": "Notification", "text": "Display is turned off"}],
    }


class JudgeTests(unittest.TestCase):
    def one(self, text, data=None):
        return judge.judge(data or evidence(), [text])[0]

    def test_within(self):
        result = self.one("within 10s after step 2: app.agent[grok].state=working")
        self.assertTrue(result["ok"])
        self.assertEqual(result["measured"], "true after 6 s")
        result = self.one("within 5s after step 2: app.agent[grok].state=working")
        self.assertFalse(result["ok"])
        self.assertIn("app.agent[grok].state=idle", result["measured"])

    def test_always_and_never(self):
        self.assertTrue(self.one("always from step 2 to step 3: app.hold=true")["ok"])
        result = self.one("always from step 2 to end: app.hold=true")
        self.assertFalse(result["ok"])
        self.assertIn("false after 70 s, in 30 of 100 samples", result["measured"])
        self.assertTrue(self.one("never from step 2 to step 3: sleepdisabled=0")["ok"])
        self.assertFalse(self.one("never from start to end: sleepdisabled=0")["ok"])

    def test_at_and_offsets(self):
        self.assertTrue(self.one("at end: sleepdisabled=0")["ok"])
        self.assertTrue(self.one("at step 3 + 10s: app.hold=false")["ok"])
        self.assertTrue(self.one("at step 3 - 5s: lid=closed")["ok"])
        self.assertTrue(self.one("at step 3 start: lid=closed")["ok"])
        self.assertTrue(self.one("within 20s after step 3: sleepdisabled=0")["ok"])
        self.assertFalse(self.one("within 10s after step 3: sleepdisabled=0")["ok"])

    def test_heartbeat_gap(self):
        self.assertEqual(self.one("heartbeat gap from step 2 to step 3 < 15s")["measured"], "largest gap 2 s")
        data = evidence()
        data["heartbeat"] = [t for t in data["heartbeat"] if not 30 < t < 60]
        result = self.one("heartbeat gap from step 2 to step 3 < 15s", data)
        self.assertFalse(result["ok"])
        self.assertEqual(result["measured"], "largest gap 30 s")

    def test_power_log(self):
        self.assertTrue(self.one("log from step 2 to step 3 has no Sleep,Wake,DarkWake")["ok"])
        self.assertFalse(self.one("log from start to end has no Sleep")["ok"])
        self.assertEqual(self.one("log within 60s after step 3 has Sleep")["measured"], "1 line of Sleep, first after 20 s")
        self.assertFalse(self.one("log within 10s after step 3 has Sleep")["ok"])
        data = evidence()
        data["log"] = None
        self.assertEqual(self.one("log from start to end has no Sleep", data)["measured"], "the power log was not read")

    def test_keys_and_commands(self):
        self.assertTrue(self.one("key chime is yes")["ok"])
        self.assertFalse(self.one("key glow is yes")["ok"])
        self.assertTrue(self.one("key glow is no")["ok"])
        self.assertEqual(self.one("key other is yes")["measured"], "answer: none")
        self.assertTrue(self.one("exit seven == 7")["ok"])
        self.assertFalse(self.one("exit seven == 0")["ok"])
        self.assertTrue(self.one("out refused contains not running")["ok"])
        self.assertFalse(self.one("exit missing == 0")["ok"])

    def test_a_step_that_was_not_reached_fails(self):
        result = self.one("within 10s after step 9: lid=open")
        self.assertFalse(result["ok"])
        self.assertEqual(result["measured"], "the run did not reach this step")

    def test_info_measures_and_never_fails(self):
        result = self.one("info within 5s after step 2: app.agent[grok].state=working")
        self.assertTrue(result["ok"])
        self.assertTrue(result["info"])
        self.assertIn("not true in 5 s", result["measured"])

    def test_bad_rules_are_errors(self):
        for text in ["sometimes lid=open", "within 10s after step 2: lid closed", "at noon: lid=open", "always from start to end: what=1"]:
            with self.assertRaises(judge.CheckError):
                judge.parse_check(text)

    def test_verdict_names_the_first_failed_rule_with_its_value(self):
        results = judge.judge(evidence(), ["key chime is yes", "within 10s after step 3: sleepdisabled=0", "at end: lid=closed"])
        result, reason = judge.verdict(results)
        self.assertEqual(result, "fail")
        self.assertTrue(reason.startswith("within 10s after step 3: sleepdisabled=0 (not true in 10 s"))
        self.assertEqual(judge.verdict(results[:1]), ("pass", "key chime is yes (answer: yes)"))
        self.assertEqual(judge.verdict(results[:1], "step 2 timed out")[0], "fail")


if __name__ == "__main__":
    unittest.main()
