"""The result board: test by build, the last result and its date. It is
made from the verdict files and from nothing else."""
import html
import os
import re
import time

from . import config

WORDS = {"pass": "PASS", "fail": "FAIL", "aborted": "ABORTED"}


def _build_key(build):
    return [int(part) for part in re.findall(r"\d+", build or "")]


def table(tests, verdicts):
    """(builds, rows). A row is a test with its last verdict per build.
    A test that was run and has no file any more still has its row."""
    last = {}
    for verdict in verdicts:
        if verdict.get("test") and verdict.get("build"):
            last[(verdict["test"], verdict["build"])] = verdict
    builds = sorted({build for _, build in last}, key=_build_key)
    known = {test_id: test for test_id, test in tests.items()}
    order = sorted(known.values(), key=lambda test: (test["layer"], test["area"], test["id"]))
    rows = [{"id": test["id"], "title": test["title"], "area": test["area"], "layer": test["layer"], "minutes": test["minutes"],
             "cells": [last.get((test["id"], build)) for build in builds]} for test in order]
    gone = sorted({test_id for test_id, _ in last} - set(known))
    rows += [{"id": test_id, "title": "(no test file)", "area": "", "layer": 0, "minutes": 0,
              "cells": [last.get((test_id, build)) for build in builds]} for test_id in gone]
    return builds, rows


def cell(verdict):
    if not verdict:
        return "never run"
    day = time.strftime("%m-%d", time.localtime(verdict.get("ended", 0)))
    return f"{WORDS.get(verdict['result'], verdict['result'])} {day}"


def text(tests, verdicts):
    builds, rows = table(tests, verdicts)
    lines = []
    width = max([len(row["id"]) for row in rows] + [4])
    head = f"{'test':<{width}}  " + "  ".join(f"{build:<13}" for build in builds) if builds else f"{'test':<{width}}  no run yet"
    lines.append(head)
    for row in rows:
        cells = "  ".join(f"{cell(verdict):<13}" for verdict in row["cells"]) if builds else "never run"
        lines.append(f"{row['id']:<{width}}  {cells}")
    done = sum(1 for row in rows if any(row["cells"]))
    lines.append("")
    lines.append(f"{done} of {len(rows)} tests have a result.")
    return "\n".join(lines)


STYLE = """
:root { color-scheme: dark; }
body { margin: 0; padding: 32px 16px; background: #0d0f12; color: #d7dbe0; font: 400 14px/1.5 -apple-system, "Helvetica Neue", sans-serif; }
main { max-width: 1100px; margin: 0 auto; }
h1 { font-size: 20px; font-weight: 500; margin: 0 0 4px; }
p { margin: 0 0 24px; color: #8b939e; }
.wrap { overflow-x: auto; }
table { border-collapse: collapse; width: 100%; }
th, td { text-align: left; padding: 7px 12px; border-bottom: 1px solid #1d2229; white-space: nowrap; font-weight: 400; }
th { color: #8b939e; font-weight: 500; }
td.title { white-space: normal; color: #a9b0ba; }
.pass { color: #5fd38d; } .fail { color: #ff6b6b; } .aborted { color: #e6b450; } .never { color: #4d5560; }
.why { color: #8b939e; white-space: normal; font-size: 12px; }
"""


def page(tests, verdicts, now):
    """One file with no script and no link to anything."""
    builds, rows = table(tests, verdicts)
    out = ["<!doctype html>", '<html lang="en"><head><meta charset="utf-8">',
           '<meta name="viewport" content="width=device-width, initial-scale=1">', "<title>Agent Caffeine tests</title>",
           f"<style>{STYLE}</style></head><body><main>", "<h1>Agent Caffeine tests</h1>",
           f"<p>The last result of each test on each build. Written {time.strftime('%Y-%m-%d %H:%M', time.localtime(now))}</p>",
           '<div class="wrap"><table>', "<tr><th>Test</th><th>Layer</th><th>Area</th><th>What</th>"
           + "".join(f"<th>{html.escape(build)}</th>" for build in builds) + "</tr>"]
    for row in rows:
        cells = ""
        for verdict in row["cells"]:
            if not verdict:
                cells += '<td class="never">never run</td>'
                continue
            why = f'<div class="why">{html.escape(verdict.get("reason", ""))}</div>' if verdict["result"] != "pass" else ""
            cells += f'<td class="{html.escape(verdict["result"])}">{html.escape(cell(verdict))}{why}</td>'
        out.append(f"<tr><td>{html.escape(row['id'])}</td><td>{row['layer']}</td><td>{html.escape(row['area'])}</td>"
                   f"<td class=\"title\">{html.escape(row['title'])}</td>{cells}</tr>")
    out.append("</table></div></main></body></html>")
    return "\n".join(out) + "\n"


def write_page(tests, verdicts, now):
    os.makedirs(config.evidence_root(), mode=0o700, exist_ok=True)
    path = os.path.join(config.evidence_root(), "board.html")
    with open(path, "w", encoding="utf-8") as file:
        file.write(page(tests, verdicts, now))
    return path
