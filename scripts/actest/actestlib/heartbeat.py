"""The heartbeat writer: a process of its own that appends the time to a
file every 2 seconds. A sleeping Mac writes nothing, so the largest hole
in the file says if the Mac slept. Started and stopped by the runner:

    python3 -m actestlib.heartbeat <file>
"""
import os
import signal
import sys
import time

INTERVAL = 2.0


def read(path):
    """The stamps of a heartbeat file, in order."""
    stamps = []
    try:
        with open(path, encoding="utf-8") as file:
            for line in file:
                try:
                    stamps.append(float(line))
                except ValueError:
                    continue
    except OSError:
        pass
    return stamps


def main(path):
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    parent = os.getppid()
    with open(path, "a", encoding="utf-8") as file:
        # A runner that is gone left no one to stop this writer.
        while os.getppid() == parent:
            file.write(f"{time.time():.3f}\n")
            file.flush()
            time.sleep(INTERVAL)


if __name__ == "__main__":
    main(sys.argv[1])
