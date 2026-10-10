import io
import os
import shutil
import tempfile
import unittest

from actestlib import board, cli, config, store, ui

TESTS = {
    "HELP-03": {"id": "HELP-03", "title": "The app is killed", "area": "help", "layer": 1, "minutes": 3},
    "DET-GROK-02": {"id": "DET-GROK-02", "title": "Grok <quiet>", "area": "det", "layer": 1, "minutes": 4},
}


def verdict(test, build, result, ended, reason="x"):
    return {"test": test, "build": build, "result": result, "ended": ended, "reason": reason}


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


if __name__ == "__main__":
    unittest.main()
