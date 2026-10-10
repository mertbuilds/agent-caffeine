import unittest

from actestlib import parse

PMSET = """System-wide power settings:
 SleepDisabled\t\t1
Currently in use:
 standby              1
 sleep                0 (sleep prevented by caffeinate, caffeinagent)
 displaysleep         10
"""

ASSERTIONS = """Assertion status system-wide:
   PreventSystemSleep             1
Listed by owning process:
   pid 77854(caffeinate): [0x000b3a87000198bb] 00:03:57 PreventUserIdleSystemSleep named: "caffeinate command-line tool"
   pid 532(powerd): [0x000b19e1000985be] 01:03:20 UserIsActive named: "com.apple.powermanagement.lidopen"
   pid 75087(caffeinagent): [0x000b3987000197c8] 00:00:01 PreventUserIdleSystemSleep named: "Agent Caffeine: My Secret Tool is working"
\tTimeout will fire in 118 secs Action=TimeoutActionRelease
   pid 75087(caffeinagent): [0x000b3987000797c9] 00:00:01 PreventSystemSleep named: "Agent Caffeine: My Secret Tool is working"
"""

SCHED = """Scheduled power events:
 [0]  wake at 10/10/2026 16:34:31 by 'com.apple.alarm.user-invisible-com.apple.calaccessd.travelEngine.periodicRefreshTimer'
 [1]  wake at 10/11/2026 02:58:24 by 'com.caffeinagent.app.wake'
"""

LOG = """2026-10-10 12:36:17 +0300 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to smc Using BATT (Charge:37%) 5 secs
2026-10-10 12:36:22 +0300 Sleep               \tEntering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using Batt (Charge:37%) 11 secs
2026-10-10 12:36:24 +0300 Wake Requests       \t[*process=dasd request=SleepService info="com.apple.dasd"]
2026-10-10 12:36:25 +0300 Assertions          \tPID 100(secretapp) Created PreventUserIdleSystemSleep "Secret title"
2026-10-10 12:36:33 +0300 Wake                \tDarkWake to FullWake from Deep Idle [CDNVAP] : due to Notification Using AC (Charge:37%)
2026-10-10 12:36:37 +0300 Notification        \tDisplay is turned off
"""


class ParseTests(unittest.TestCase):
    def test_pmset(self):
        self.assertEqual(parse.sleep_disabled(PMSET), 1)
        self.assertIsNone(parse.sleep_disabled("Currently in use:\n sleep 1\n"))
        self.assertEqual(parse.timers(PMSET), {"sleep": 0, "displaysleep": 10})

    def test_battery(self):
        ac = "Now drawing from 'AC Power'\n -InternalBattery-0 (id=1)\t100%; charged; 0:00 remaining present: true\n"
        self.assertEqual(parse.battery(ac), {"power": "ac", "charge": 100})
        battery = "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=1)\t64%; discharging; 3:10 remaining\n"
        self.assertEqual(parse.battery(battery), {"power": "battery", "charge": 64})

    def test_lid(self):
        self.assertEqual(parse.lid('  |   "AppleClamshellCausesSleep" = Yes\n  |   "AppleClamshellState" = No\n'), "open")
        self.assertEqual(parse.lid('"AppleClamshellState" = Yes'), "closed")
        self.assertIsNone(parse.lid(""))

    def test_assertions_keep_kinds_and_process_names_only(self):
        found = parse.assertions(ASSERTIONS, 75087)
        self.assertEqual(found, {"ours": ["PreventSystemSleep", "PreventUserIdleSystemSleep"], "others": ["caffeinate"]})
        self.assertNotIn("Secret", str(found))
        self.assertEqual(parse.assertions(ASSERTIONS, None)["ours"], [])

    def test_schedule(self):
        events = parse.schedule(SCHED)
        self.assertEqual(len(events), 2)
        self.assertEqual(events[1], {"kind": "wake", "at": "10/11/2026 02:58:24", "owner": "com.caffeinagent.app.wake"})
        self.assertEqual(parse.schedule("Scheduled power events:\n"), [])

    def test_app_pid(self):
        table = "  532 /usr/libexec/powerd\n75087 /Applications/agent caffeine.app/Contents/MacOS/caffeinagent\n75119 Contents/MacOS/CaffeinagentHelper\n 9000 /tmp/build/caffeinagent.app/Contents/MacOS/caffeinagent\n"
        self.assertEqual(parse.app_pid(table, "/Applications/Agent Caffeine.app"), 75087)
        self.assertIsNone(parse.app_pid(table, "/Applications/Other.app"))
        self.assertIsNone(parse.app_pid(table, None))

    def test_external_displays(self):
        internal = {"spdisplays_connection_type": "spdisplays_internal"}
        self.assertEqual(parse.external_displays({"SPDisplaysDataType": [{"spdisplays_ndrvs": [internal]}]}), 0)
        self.assertEqual(parse.external_displays({"SPDisplaysDataType": [{"spdisplays_ndrvs": [internal, {"_name": "x"}]}]}), 1)

    def test_power_log_is_cut_to_the_window_and_to_safe_lines(self):
        from datetime import datetime
        start = datetime.strptime("2026-10-10 12:36:20 +0300", "%Y-%m-%d %H:%M:%S %z").timestamp()
        lines = parse.power_log(LOG, start, start + 15)
        self.assertEqual([line["kind"] for line in lines], ["Sleep", "Wake"])
        self.assertNotIn("Secret", str(parse.power_log(LOG, 0, 1e12)))
        self.assertEqual(len(parse.power_log(LOG, 0, 1e12)), 4)

    def test_heartbeat_gap(self):
        self.assertEqual(parse.heartbeat_gap([2, 4, 6, 8], 0, 10), 2)
        self.assertEqual(parse.heartbeat_gap([2, 4, 30, 32], 0, 34), 26)
        self.assertEqual(parse.heartbeat_gap([], 0, 60), 60)
        self.assertEqual(parse.heartbeat_gap([1, 500], 100, 110), 10)


if __name__ == "__main__":
    unittest.main()
