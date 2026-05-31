#!/usr/bin/env python3
"""Standalone liveness checker — writes a heartbeat to `alive` as long
as a real interactive Claude Code session exists. Exits when none is found.

Uses ancestry-based logic: a genuine session traces up to a shell/terminal,
while daemon-spawned spares have `daemon run` in their parent chain.
"""
import os, sys, time

ALIVE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "alive")
INTERVAL = 3      # seconds between checks
MISSES = 4        # consecutive misses before exit


def claude_alive():
    """True only if a REAL interactive Claude Code session is running."""
    try:
        cmd = {}
        ppid = {}

        def load(pid):
            if pid in cmd:
                return
            try:
                with open(f"/proc/{pid}/cmdline") as f:
                    cmd[pid] = f.read().replace("\0", " ")
                with open(f"/proc/{pid}/status") as f:
                    for line in f:
                        if line.startswith("PPid:"):
                            ppid[pid] = int(line.split()[1])
                            break
            except OSError:
                cmd[pid] = ""
                ppid[pid] = 0

        def daemon_ancestry(pid):
            cur, depth = pid, 0
            while cur > 1 and depth < 15:
                load(cur)
                c = cmd.get(cur, "")
                if "daemon run" in c or "--bg-pty-host" in c or "--bg-spare" in c:
                    return True
                cur = ppid.get(cur, 0)
                depth += 1
            return False

        for entry in os.scandir("/proc"):
            if not entry.name.isdigit():
                continue
            pid = int(entry.name)
            try:
                with open(f"/proc/{pid}/comm") as f:
                    if "claude" not in f.read().strip().lower():
                        continue
                if "pts" not in os.readlink(f"/proc/{pid}/fd/0"):
                    continue
                load(pid)
                own = cmd.get(pid, "")
                if "statuslight" in own or "daemon run" in own:
                    continue
                if not daemon_ancestry(pid):
                    return True
            except OSError:
                continue
        return False
    except OSError:
        return True   # never exit on a scan failure


def main():
    # Write initial heartbeat immediately so the display doesn't
    # self-terminate during the first INTERVAL window.
    try:
        with open(ALIVE_FILE, "w") as f:
            f.write(str(int(time.time())))
    except OSError:
        pass

    miss = 0
    while True:
        if claude_alive():
            miss = 0
            try:
                with open(ALIVE_FILE, "w") as f:
                    f.write(str(int(time.time())))
            except OSError:
                pass
        else:
            miss += 1
            if miss >= MISSES:
                try:
                    os.remove(ALIVE_FILE)
                except OSError:
                    pass
                sys.exit(0)
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
