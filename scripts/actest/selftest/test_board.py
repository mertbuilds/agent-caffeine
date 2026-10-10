import io
import os
import shutil
import tempfile
import unittest

from actestlib import board, catalog, cli, config, judge, store, ui
from selftest import fakes

TESTS = {
    "HELP-03": {"id": "HELP-03", "title": "The app is killed", "area": "help", "layer": 1, "minutes": 3},
    "DET-GROK-02": {"id": "DET-GROK-02", "title": "Grok <quiet>", "area": "det", "layer": 1, "minutes": 4},
}


def verdict(test, build, result, ended, reason="x", **more):
    return dict({"test": test, "build": build, "result": result, "ended": ended, "reason": reason}, **more)


SKIPPED = judge.judge({"idle": False, "keys": {"row": "yes"}}, ["key row is yes", "if idle: at end: app.hold=<false>"])
PARTIAL = verdict("HELP-03", "1.0.3 (17)", "pass", 1_791_250_000, partial=1, idle=False, checks=SKIPPED)


VERDICTS = [
    verdict("HELP-03", "1.0.2 (16)", "pass", 1_791_000_000),
    verdict("HELP-03", "1.0.3 (17)", "fail", 1_791_100_000, "at end: sleepdisabled=0 (sleepdisabled=1)"),
    verdict("HELP-03", "1.0.3 (17)", "pass", 1_791_200_000),
    verdict("OLD-01", "1.0.2 (16)", "aborted", 1_791_000_500),
    verdict("HELP-03", "1.0.10 (20)", "fail", 1_791_300_000, "a <b> reason"),
]


class BoardTests(unittest.TestCase):
    def test_the_last_result_per_build_counts(self):
        builds, rows = board.table(TESTS, VERDICTS)
        self.assertEqual(builds, ["1.0.2 (16)", "1.0.3 (17)", "1.0.10 (20)"], "Builds in the order of their numbers")
        by_id = {row["id"]: row for row in rows}
        self.assertEqual([cell and cell["result"] for cell in by_id["HELP-03"]["cells"]], ["pass", "pass", "fail"])
        self.assertEqual(by_id["DET-GROK-02"]["cells"], [None, None, None])
        self.assertEqual(by_id["OLD-01"]["title"], "(no test file)")

    def test_text(self):
        text = board.text(TESTS, VERDICTS)
        self.assertIn("HELP-03", text)
        self.assertIn("never run", text)
        self.assertIn("2 of 3 tests have a result.", text)
        self.assertIn("no run yet", board.text(TESTS, []))

    def test_the_page_stands_alone_and_has_no_script(self):
        page = board.page(TESTS, VERDICTS, 1_791_300_100)
        self.assertNotIn("<script", page)
        self.assertNotIn("http", page)
        self.assertNotIn("font-weight: 600", page)
        self.assertNotIn("bold", page)
        self.assertIn("Grok &lt;quiet&gt;", page)
        self.assertIn("a &lt;b&gt; reason", page)
        self.assertIn('class="never"', page)
        self.assertNotIn(chr(8212), page)

    def test_a_partial_pass_never_shows_as_a_whole_pass(self):
        day = "10-0"
        cell = board.cell(PARTIAL)
        self.assertTrue(cell.startswith("PASS (partial: 1 check needs an idle Mac) "), cell)
        self.assertEqual(board.cell(dict(PARTIAL, partial=3))[:41], "PASS (partial: 3 checks need an idle Mac)")
        self.assertRegex(board.cell(dict(PARTIAL, partial=0)), r"^PASS \d\d-\d\d$")
        self.assertRegex(board.cell(verdict("HELP-03", "1.0.3 (17)", "fail", 1, partial=1)), r"^FAIL \d\d-\d\d$", "Only a pass is partial")
        self.assertRegex(board.cell(verdict("HELP-03", "1.0.3 (17)", "skipped", 1)), r"^SKIPPED \d\d-\d\d$")
        text = board.text(TESTS, VERDICTS[:3] + [PARTIAL])
        row = next(line for line in text.splitlines() if line.startswith("HELP-03"))
        self.assertIn("PASS (partial: 1 check needs an idle Mac)", row)
        self.assertNotRegex(row, r"PASS \d\d-\d\d\s+PASS \d\d-\d\d", "The newer partial pass is the cell, not the older whole one")
        head = text.splitlines()[0]
        self.assertEqual(head.index("1.0.3 (17)"), row.index("PASS (partial"), "The columns stay in line")
        page = board.page(TESTS, VERDICTS[:3] + [PARTIAL], 1_791_300_100)
        self.assertIn('<td class="partial">PASS (partial: 1 check needs an idle Mac)', page)
        self.assertIn('<div class="why">not judged: if idle: at end: app.hold=&lt;false&gt;</div>', page)
        self.assertNotIn("not judged: key row is yes", page)
        self.assertEqual(page.count('class="pass"'), 1, "The whole pass of the older build")
        self.assertNotIn(chr(8212), page)


class StoreAndReportTests(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp(prefix="actest-selftest-")
        os.environ["ACTEST_HOME"] = self.home

    def tearDown(self):
        del os.environ["ACTEST_HOME"]
        shutil.rmtree(self.home, ignore_errors=True)

    def test_runs_are_numbered_per_day_and_are_outside_the_folder_of_the_app(self):
        first = store.new_run("HELP-03", 1_791_200_000)
        second = store.new_run("HELP-03", 1_791_200_000)
        self.assertTrue(first.endswith("-HELP-03-1"))
        self.assertTrue(second.endswith("-HELP-03-2"))
        self.assertNotIn(config.BUNDLE_ID, first)
        del os.environ["ACTEST_HOME"]
        self.assertTrue(config.evidence_root().endswith("Library/Application Support/Agent Caffeine Tests"))
        self.assertNotIn(config.BUNDLE_ID, config.evidence_root())
        os.environ["ACTEST_HOME"] = self.home

    def test_the_board_is_made_from_the_verdict_files(self):
        run_dir = store.new_run("HELP-03", 1_791_200_000)
        store.write_verdict(run_dir, verdict("HELP-03", "1.0.3 (17)", "pass", 1_791_200_060))
        found = store.verdicts()
        self.assertEqual([(item["test"], item["result"]) for item in found], [("HELP-03", "pass")])
        path = board.write_page(TESTS, found, 1_791_200_100)
        self.assertTrue(path.startswith(self.home))

    def test_a_timeline_keeps_what_it_saw_and_drops_a_cut_line(self):
        run_dir = store.new_run("HELP-03", 1_791_200_000)
        timeline = store.Timeline(run_dir)
        timeline.add({"t": 1.0, "step": 1, "lid": "open", "app": None})
        timeline.add({"t": 2.0, "step": 1, "lid": "closed", "app": None})
        with open(timeline.path, "a", encoding="utf-8") as file:
            file.write('{"t": 3.0, "ste')
        samples = store.read_timeline(run_dir)
        self.assertEqual([sample["lid"] for sample in samples], ["open", "closed"])
        self.assertEqual(len(cli.changes(samples)), 1)
        self.assertIn("lid: open -> closed", cli.changes(samples)[0])

    def test_report_prints_the_run(self):
        run_dir = store.new_run("HELP-03", 1_791_200_000)
        store.write_verdict(run_dir, verdict("HELP-03", "1.0.3 (17)", "pass", 1_791_200_060))
        store.write_run(run_dir, {"test": "HELP-03"})
        out = io.StringIO()

        class Args:
            run = "HELP-03-1"

        self.assertEqual(cli.cmd_report(Args, None, ui.UI(plain=True, out=out)), 0)
        self.assertIn('"result": "pass"', out.getvalue())
        self.assertEqual(cli.cmd_report(type("A", (), {"run": "nothing"}), None, ui.UI(plain=True, out=out)), 2)

    def listed(self, world, busy):
        out = io.StringIO()
        args = type("Args", (), {"area": None, "layer": None, "busy": busy})
        self.assertEqual(cli.cmd_list(args, fakes.FakeEnv(world), ui.UI(plain=True, out=out)), 0)
        return out.getvalue()

    def test_list_says_when_each_test_can_start(self):
        said = self.listed(lambda t: {"state": fakes.state()}, busy=False)
        lines = said.splitlines()
        self.assertRegex(next(line for line in lines if line.startswith("CLI-01 ")), r" min  any time     hold --for")
        self.assertRegex(next(line for line in lines if line.startswith("HELP-02 ")), r" min  needs idle   The sleep flag")
        self.assertRegex(next(line for line in lines if line.startswith("WAKE-E01 ")), r" min  needs sleep  Does a wake alarm")
        self.assertEqual(lines[lines.index(next(line for line in lines if line.startswith("CLI-01 "))) + 2].strip(),
                         "2 of 6 rules are judged on an idle Mac only")
        total = len(catalog.load_all())
        self.assertEqual(lines[-1], f"Of all: any time {total - 10}, needs idle 8, needs sleep 2.")
        self.assertNotIn("holds now", said, "A plain list does not look at the Mac")

    def test_list_busy_leaves_out_what_cannot_start_now(self):
        total = len(catalog.load_all())
        env_world = lambda t: {"awake": True, "flag": 1, "state": fakes.state(hold=True, flag=True)}
        said = self.listed(env_world, busy=True)
        self.assertTrue(said.startswith("Agent Caffeine holds now: working.\n"))
        ids = {line.split()[0] for line in said.splitlines() if " L1 " in line}
        self.assertEqual(len(ids), total - 10)
        self.assertTrue({"CLI-01", "CLI-07", "CLI-09", "HELP-03", "HOLD-04", "HELP-21"} <= ids)
        self.assertFalse({"HELP-02", "CLI-10", "DET-GEN-01", "WAKE-18", "WAKE-E01", "WAKE-E02", "WAKE-E06"} & ids)
        self.assertIn(f"{total - 10} of {total} tests can start now", said)
        self.assertTrue(said.endswith(f"Of all: any time {total - 10}, needs idle 8, needs sleep 2.\n"), "What was left out is counted")
        said = self.listed(lambda t: {"state": fakes.state()}, busy=True)
        self.assertTrue(said.startswith("Nothing holds the Mac awake now.\n"))
        self.assertIn(f"{total} of {total} tests can start now", said)
        said = self.listed(lambda t: {"state": fakes.state(on=False)}, busy=True)
        self.assertIn(f"{total} of {total} tests can start now", said, "The list looks at the agents only. The preflight says the rest")
        said = self.listed(lambda t: {"pid": None}, busy=True)
        self.assertTrue(said.startswith("It is not known if Agent Caffeine holds now."))
        self.assertIn(f"{total - 10} of {total} tests can start now", said)

    def test_list_busy_only_reads(self):
        env = fakes.FakeEnv(lambda t: {"state": fakes.state()})
        out = io.StringIO()
        cli.cmd_list(type("Args", (), {"area": None, "layer": None, "busy": True}), env, ui.UI(plain=True, out=out))
        self.assertTrue(all(args[:2] in (("pmset", "-g"),) or args[0] in ("ioreg", "ps") for args in env.commands), set(env.commands))
        self.assertEqual(env.tool_calls, [])


if __name__ == "__main__":
    unittest.main()
