import unittest

from actestlib import expr

APP = {
    "at": 100, "on": True, "decision": {"hold": True, "headline": "working", "stop": False, "assertion": True},
    "flag": {"wanted": True, "helper": "enabled", "setup": "ready", "set": True}, "gate": "open",
    "app": {"pid": 77, "version": "1.0.3", "build": "17"},
    "agents": [
        {"id": "grok", "pid": 1, "state": "idle", "why": "atPrompt", "level": "state"},
        {"id": "grok", "pid": 2, "state": "working", "why": "reportsBusy", "level": "state", "hold": "working"},
        {"id": "claude", "pid": 3, "state": "waiting", "why": "asksPermission", "level": "state"},
    ],
    "holds": [{"id": "0a1b2c3d", "kind": "timed", "start": 90, "end": 150}],
    "jobs": {"on": True, "status": "alarmSet", "alarm": {"at": 500, "fireAt": 560}, "holds": [],
             "history": [{"kind": "alarmSet", "at": 95}, {"kind": "alarmCancelled", "at": 40}]},
    "notices": [{"kind": "waiting", "at": 98}], "chimeAt": 97,
    "network": {"online": False, "offlineSeconds": 61, "limitSeconds": 60, "agentsReleased": True},
    "hotspot": {"on": True, "configured": True, "state": "joined", "since": 96},
    "closedLid": {"since": 10, "heldSeconds": 181, "limitSeconds": 180, "limitDrop": 30, "stop": "closedLidTime", "agentsReleased": True},
}
SAMPLE = {
    "t": 100, "lid": "closed", "power": "battery", "charge": 64, "sleepdisabled": 1, "app_pid": 77, "app": APP,
    "assertions": ["PreventSystemSleep", "PreventUserIdleSystemSleep"], "others": ["caffeinate"],
    "sched": [{"kind": "wake", "owner": "com.caffeinagent.app.wake"}], "status": {"awake": True, "stopped": False},
    "probe": {"skill_claude": True, "job_lines": 3}, "child": {"hold": "running"},
}


class ExprTests(unittest.TestCase):
    def ok(self, text, sample=SAMPLE, since=None):
        return expr.holds(text, sample, since)

    def test_the_watches(self):
        self.assertTrue(self.ok("lid=closed"))
        self.assertFalse(self.ok("lid=open"))
        self.assertTrue(self.ok("power=battery and charge>=40"))
        self.assertTrue(self.ok("sleepdisabled=1"))
        self.assertTrue(self.ok("sleepdisabled == 1"))
        self.assertTrue(self.ok("assertions=2 and others=1"))
        self.assertTrue(self.ok("sched.ours=true"))
        self.assertTrue(self.ok("sched.byhand=false"))
        self.assertTrue(self.ok("status.awake=true and status.stopped=false"))
        self.assertTrue(self.ok("probe.skill_claude=true and probe.job_lines>=3"))
        self.assertTrue(self.ok("child.hold=running"))

    def test_the_sessions_that_the_app_does_not_see(self):
        seen = dict(SAMPLE, sessions={"live": 3, "unseen": []})
        self.assertTrue(self.ok("sessions.unseen=0 and sessions.live>=1", seen))
        missed = dict(SAMPLE, sessions={"live": 3, "unseen": [20946, 69479]})
        self.assertTrue(self.ok("sessions.unseen=2", missed))
        self.assertFalse(self.ok("sessions.unseen=0", missed))
        self.assertEqual(expr.reading("sessions.unseen=0", missed), "sessions.unseen=2")
        # Without the state of the app nobody knows, and that is no pass.
        for sample in (SAMPLE, dict(SAMPLE, sessions=None)):
            self.assertFalse(self.ok("sessions.unseen=0", sample))
            self.assertFalse(self.ok("sessions.live>=1", sample))

    def test_the_state_of_the_app(self):
        self.assertTrue(self.ok("app.running=true and app.state=true"))
        self.assertTrue(self.ok("app.hold=true"))
        self.assertTrue(self.ok("app.headline=working"))
        self.assertTrue(self.ok("app.flag=true and app.wanted=true and app.helper=enabled"))
        self.assertTrue(self.ok("app.paused=false and app.on=true"))
        self.assertTrue(self.ok("app.holds=1 and app.jobholds=0"))
        self.assertTrue(self.ok("app.alarm=true and app.jobs.status=alarmSet"))
        self.assertTrue(self.ok("app.history[alarmSet]=1 and app.history[alarmSet].age<=5"))
        self.assertTrue(self.ok("app.notice[waiting]=1 and app.notice[finished]=0"))
        self.assertTrue(self.ok("app.chime.age<5"))
        self.assertTrue(self.ok("app.build=17"))

    def test_the_network_and_the_rules_that_let_go_of_the_agents(self):
        self.assertTrue(self.ok("app.network.online=false"))
        self.assertTrue(self.ok("app.network.agentsReleased=true and app.network.offlineSeconds>=60"))
        self.assertTrue(self.ok("app.network.limitSeconds=60"))
        self.assertTrue(self.ok("app.closedLid.agentsReleased=true and app.closedLid.stop=closedLidTime"))
        self.assertTrue(self.ok("app.closedLid.limitSeconds=180"))
        online = dict(SAMPLE, app=dict(APP, network={"online": True, "limitSeconds": 600, "agentsReleased": False}, closedLid=None))
        self.assertTrue(self.ok("app.network.online=true and app.network.agentsReleased=false", online))
        self.assertTrue(self.ok("app.network.offlineSeconds=none", online))
        self.assertTrue(self.ok("app.closedLid.agentsReleased=none", online), "No closed-lid period")
        # A build without the fields says nothing, and that is no pass.
        old = dict(SAMPLE, app={key: value for key, value in APP.items() if key != "network"})
        self.assertFalse(self.ok("app.network.online=false", old))
        self.assertFalse(self.ok("app.network.agentsReleased=true", old))
        self.assertEqual(expr.reading("app.network.agentsReleased=true", SAMPLE), "app.network.agentsReleased=true")

    def test_the_hotspot_reads_as_its_switch_and_its_state(self):
        self.assertTrue(self.ok("app.hotspot.on=true and app.hotspot.configured=true"))
        self.assertTrue(self.ok("app.hotspot.state=joined and app.hotspot.since>=90"))
        self.assertTrue(self.ok("app.hotspot.state!=notFound"))
        failed = dict(SAMPLE, app=dict(APP, hotspot={"on": True, "configured": True, "state": "failed:wrongPassword", "since": 96}))
        self.assertTrue(self.ok("app.hotspot.state=failed:wrongPassword", failed))
        self.assertFalse(self.ok("app.hotspot.state=failed:noPermission", failed))
        off = dict(SAMPLE, app=dict(APP, hotspot={"on": False, "configured": False, "state": "idle"}))
        self.assertTrue(self.ok("app.hotspot.on=false and app.hotspot.state=idle and app.hotspot.since=none", off))
        # A build without the feature says nothing, and that is no pass.
        old = dict(SAMPLE, app={key: value for key, value in APP.items() if key != "hotspot"})
        self.assertFalse(self.ok("app.hotspot.on=true", old))
        self.assertFalse(self.ok("app.hotspot.state=joined", old))
        self.assertFalse(self.ok("app.hotspot.state=idle", old))
        self.assertEqual(expr.reading("app.hotspot.state=joined", SAMPLE), "app.hotspot.state=joined")

    def test_an_agent_reads_as_its_busiest_instance(self):
        self.assertTrue(self.ok("app.agent[grok].state=working"))
        self.assertTrue(self.ok("app.agent[grok].count=2"))
        self.assertTrue(self.ok("app.agent[grok].why=reportsBusy"))
        self.assertTrue(self.ok("app.agent[claude].state=waiting"))
        self.assertTrue(self.ok("app.agent[hermes-agent].state=gone"))
        self.assertTrue(self.ok("app.agent[hermes-agent].count=0"))
        self.assertTrue(self.ok("app.agent[*].state=working"))

    def test_a_hold_of_the_test_is_found_by_its_id(self):
        sample = dict(SAMPLE, own={"first": "0a1b2c3d", "second": "ffff0000"})
        self.assertTrue(self.ok("held.first=true and held.second=false", sample))
        self.assertTrue(self.ok("held.other=none", sample), "No step of that name made a hold")
        self.assertTrue(self.ok("held.first=none"), "The runner recorded no id")
        self.assertTrue(self.ok("held.first=none", dict(sample, app=None)), "No state of the app is not the same as no hold")
        expr.check("held.first=true")

    def test_time_counts_from_the_start_of_the_step(self):
        self.assertTrue(self.ok("time>=30s", since=70))
        self.assertFalse(self.ok("time>=30s", since=71))
        self.assertTrue(self.ok("time>=1m", since=40))

    def test_or_and_and(self):
        self.assertTrue(self.ok("lid=open or power=battery"))
        self.assertFalse(self.ok("lid=open or power=ac and charge>10"))
        self.assertTrue(self.ok("lid!=open"))

    def test_a_missing_value_is_none_and_never_passes_a_comparison(self):
        bare = {"t": 5, "app": None, "app_pid": None}
        self.assertFalse(self.ok("app.hold=true", bare))
        self.assertFalse(self.ok("app.hold=false", bare))
        self.assertTrue(self.ok("app.hold=none", bare))
        self.assertFalse(self.ok("charge>=40", bare))
        self.assertTrue(self.ok("app.running=false", bare))
        self.assertFalse(self.ok("sleepdisabled=0", bare))
        self.assertFalse(self.ok("sched.ours=false", bare), "Not sampled is not the same as no alarm")

    def test_true_is_not_one(self):
        self.assertFalse(self.ok("app.hold=1"))
        self.assertFalse(self.ok("sleepdisabled=true"))

    def test_bad_conditions_are_errors(self):
        with self.assertRaises(expr.ExprError):
            expr.check("lid closed")
        with self.assertRaises(expr.ExprError):
            expr.check("nonsense=1")
        expr.check("app.agent[grok].state=working and time>=10s")

    def test_reading_says_what_was_measured(self):
        self.assertEqual(expr.reading("lid=open and app.hold=true", SAMPLE), "lid=closed, app.hold=true")


if __name__ == "__main__":
    unittest.main()
