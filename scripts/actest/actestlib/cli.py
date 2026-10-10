"""actest: test Agent Caffeine together, one step at a time.

    actest list [--area X] [--layer N]   the tests, with the last result per build
    actest list --busy                   only the tests that can start as the agents are now
    actest check                         the preflight alone
    actest run <id> [<id> ...]           run tests: preflight, steps, verdict, cleanup
    actest board                         the result board, as text and as board.html
    actest report <run-id>               everything recorded for one run
    actest abort                         stop the run that is under way and clean up

    --plain   no colour and no screen clearing
"""
import argparse
import json
import os
import subprocess
import sys
import time

from . import board, catalog, cleanup, env as environment, preflight, runner, sampler, store, ui as interface

WATCHED = ("lid", "power", "sleepdisabled", "app.hold", "app.headline", "app.flag", "app.running", "app.alarm", "app.gate")


def _tests(out):
    try:
        return catalog.load_all()
    except catalog.TestError as error:
        out.line(f"A test file is wrong: {error}")
        raise SystemExit(2) from error


def cmd_list(args, env, out):
    tests = _tests(out)
    chosen = {test["id"]: test for test in catalog.select(tests, args.area, args.layer)}
    every = len(chosen)
    kinds = [catalog.when(test) for test in chosen.values()]
    if args.busy:
        sample = sampler.take(env)
        holding = sampler.holding(sample)
        headline = ((sample.get("app") or {}).get("decision") or {}).get("headline")
        if holding is None:
            out.line("It is not known if Agent Caffeine holds now. Only the tests for any time are listed.")
        elif holding:
            out.line("Agent Caffeine holds now" + (f": {headline}." if headline else "."))
        else:
            out.line("Nothing holds the Mac awake now.")
        out.line()
        chosen = {test_id: test for test_id, test in chosen.items() if preflight.free_now(sample, test)}
    builds, rows = board.table(chosen, store.verdicts())
    for row in rows:
        if row["id"] not in chosen:
            continue
        test = chosen[row["id"]]
        results = ", ".join(f"{build}: {board.cell(verdict)}" for build, verdict in zip(builds, row["cells"]) if verdict) or "never run"
        out.line(f"{row['id']:<13} L{row['layer']} {row['area']:<5} {row['minutes']:>4} min  {catalog.when(test):<11}  {row['title']}")
        out.line(f"{'':<13} {results}")
        if catalog.idle_rules(test):
            out.line(f"{'':<13} {catalog.idle_rules(test)} of {len(test['checks'])} rules are judged on an idle Mac only")
    minutes = sum(test["minutes"] for test in chosen.values())
    out.line()
    if args.busy:
        out.line(f"{len(chosen)} of {every} tests can start now, about {minutes} minutes. The preflight of a run says what else to fix.")
    else:
        out.line(f"{len(chosen)} tests, about {minutes} minutes.")
    out.line("Of all: " + ", ".join(f"{kind} {kinds.count(kind)}" for kind in ("any time", "needs idle", "needs sleep")) + ".")
    return 0


def cmd_check(args, env, out):
    items = preflight.check(preflight.gather(env))
    for item in items:
        out.item(item)
    stopped = preflight.blocked(items)
    out.line()
    out.line("Ready to test." if not stopped else f"Not ready: {len(stopped)} to fix. Do the first fix, then run actest check again.")
    return 1 if stopped else 0


def cmd_run(args, env, out):
    tests = _tests(out)
    missing = [test_id for test_id in args.ids if test_id not in tests]
    if missing:
        out.line(f"No such test: {', '.join(missing)}. See actest list.")
        return 2
    failed = 0
    for position, test_id in enumerate(args.ids):
        test = tests[test_id]
        out.page(f"{test_id}   {test['title']}")
        out.line(f"About {test['minutes']} minutes.")
        if test.get("risk"):
            out.line(f"Care: {test['risk']}")
        out.line()
        items = preflight.check(preflight.gather(env), test)
        stopped = preflight.blocked(items)
        for item in stopped:
            out.item(item)
        if stopped and not args.force:
            out.line()
            out.line(f"{test_id} did not start: {len(stopped)} to fix.")
            failed += 1
            continue
        verdict = runner.run_test(test, env, out)
        failed += verdict["result"] != "pass"
        if verdict["result"] == "aborted":
            break
        if position + 1 < len(args.ids):
            out.line("Press Enter for the next test.")
            env.open_keys()
            try:
                while env.key(1.0) != "enter":
                    pass
            except KeyboardInterrupt:
                break
            finally:
                env.close_keys()
    return 1 if failed else 0


def cmd_board(args, env, out):
    tests = _tests(out)
    verdicts = store.verdicts()
    out.line(board.text(tests, verdicts))
    out.line(f"Page: {board.write_page(tests, verdicts, env.now())}")
    return 0


def changes(samples):
    """The moments a watched value changed, for the reader of a report."""
    from . import expr
    last, lines = {}, []
    for sample in samples:
        for path in WATCHED:
            now = expr.show(expr.value(sample, path))
            if last.get(path) != now:
                if path in last:
                    lines.append(f"{time.strftime('%H:%M:%S', time.localtime(sample['t']))} step {sample['step']:>2}  {path}: {last[path]} -> {now}")
                last[path] = now
    return lines


def cmd_report(args, env, out):
    run_dir = store.find_run(args.run)
    if not run_dir:
        out.line(f"No run {args.run}.")
        return 2
    out.line(f"Run: {run_dir}")
    for name in ("verdict.json", "run.json"):
        out.line(f"--- {name}")
        out.line(json.dumps(store.read_json(os.path.join(run_dir, name)), indent=1, sort_keys=True))
    samples = store.read_timeline(run_dir)
    out.line(f"--- timeline.jsonl: {len(samples)} samples. The changes:")
    for line in changes(samples):
        out.line(line)
    try:
        with open(os.path.join(run_dir, "pmset-log.txt"), encoding="utf-8") as file:
            out.line("--- pmset-log.txt")
            out.line(file.read().rstrip())
    except OSError:
        out.line("--- no pmset-log.txt")
    out.line(f"--- files: {', '.join(sorted(os.listdir(run_dir)))}")
    return 0


def _command_of(pid):
    done = subprocess.run(["ps", "-p", str(pid), "-o", "command="], capture_output=True, text=True, check=False)
    return done.stdout.strip()


def cmd_abort(args, env, out):
    return cleanup.abort(env, out, _command_of)


def main(argv=None):
    parser = argparse.ArgumentParser(prog="actest", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--plain", action="store_true", help="no colour and no screen clearing")
    commands = parser.add_subparsers(dest="command", required=True)
    listing = commands.add_parser("list")
    listing.add_argument("--area")
    listing.add_argument("--layer", type=int)
    listing.add_argument("--busy", action="store_true", help="only the tests that can start as the agents are now")
    commands.add_parser("check")
    running = commands.add_parser("run")
    running.add_argument("ids", nargs="+", metavar="id")
    running.add_argument("--force", action="store_true", help="start also when the preflight says no")
    commands.add_parser("board")
    commands.add_parser("report").add_argument("run")
    commands.add_parser("abort")
    args = parser.parse_args(argv)
    out = interface.UI(plain=args.plain)
    handler = {"list": cmd_list, "check": cmd_check, "run": cmd_run, "board": cmd_board, "report": cmd_report, "abort": cmd_abort}
    return handler[args.command](args, environment.RealEnv(), out)


if __name__ == "__main__":
    sys.exit(main())
