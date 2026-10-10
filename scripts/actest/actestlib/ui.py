"""What the owner sees: plain short sentences, one step at a time."""
import sys

GREEN, RED, AMBER, DIM, BOLD, RESET = "\033[32m", "\033[31m", "\033[33m", "\033[2m", "\033[1m", "\033[0m"
MARKS = {"pass": ("PASS", GREEN), "fail": ("FAIL", RED), "unknown": ("  ? ", AMBER), "note": ("NOTE", DIM),
         "aborted": ("ABORTED", AMBER), "none": ("  - ", DIM), "skipped": ("SKIP", AMBER)}


class UI:
    def __init__(self, plain=False, out=None):
        self.out = out or sys.stdout
        self.plain = plain or not self.out.isatty()
        self._status = False

    def paint(self, text, colour):
        return text if self.plain else f"{colour}{text}{RESET}"

    def line(self, text=""):
        self._end_status()
        self.out.write(text + "\n")
        self.out.flush()

    def _end_status(self):
        if self._status:
            self.out.write("\n")
            self._status = False

    def status(self, text):
        """One line that is written over while a step waits. In plain
        mode nothing: a log has no use for a counter."""
        if self.plain:
            return
        self.out.write("\r\033[K" + self.paint(text, DIM))
        self.out.flush()
        self._status = True

    def page(self, title):
        """A new step on a clean screen."""
        self._end_status()
        if self.plain:
            self.out.write("\n" + "-" * 60 + "\n")
        else:
            self.out.write("\033[2J\033[H")
        self.line(self.paint(title, BOLD))
        self.line()

    def item(self, item):
        word, colour = MARKS[item["status"]]
        self.line(f"{self.paint(word, colour)}  {item['name']:<14} {item['text']}")
        if item.get("fix"):
            self.line(f"      {'':<14} Fix: {item['fix']}")

    def banner(self, result, test_id, reason, note=None):
        """`note` stands after the word: a pass that is not whole says so."""
        word, colour = MARKS.get(result, MARKS["fail"])
        if note:
            word, colour = f"{word} ({note})", AMBER
        bar = "=" * 60
        self.line()
        self.line(self.paint(bar, colour))
        self.line(self.paint(f"   {word.strip()}   {test_id}", colour if self.plain else colour + BOLD))
        self.line(self.paint(bar, colour))
        self.line(reason)
        self.line()
