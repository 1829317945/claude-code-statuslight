#!/usr/bin/env python3
"""Claude Code status light — three floating dots, top-left of the desktop.

States (read from the `state` file next to this script):
  busy -> yellow solid        (Claude is working)
  wait -> red blinking        (Claude needs your choice)
  done -> green blink x6, then solid   (turn finished)
  idle -> all dim             (standby)

Hooks only ever write one word into the state file; ALL animation lives here,
driven by a single ~80ms QTimer. CPU is ~0 at rest. Rendered with Qt so the
window is truly transparent on WSLg — the dots float with no background panel.
"""
import os
from PySide6 import QtCore, QtGui, QtWidgets

HERE = os.path.dirname(os.path.abspath(__file__))
STATE_FILE = os.path.join(HERE, "state")

TICK_MS = 80           # animation + poll cadence
BLINK_TICKS = 6        # red on/off half-period (~480ms)
DONE_BLINK_HALF = 3    # green on/off half-period during the 6 flashes
DONE_FLASHES = 6       # number of green flashes before going solid
WATCHDOG_TICKS = 38    # ~3s: how often to check Claude Code is still alive
WATCHDOG_MISSES = 4    # quit after this many consecutive misses (~12s grace)
RAISE_TICKS = 25       # ~2s: re-assert top-most so other apps can't cover it

# bright / dim colors per channel (R,G,B)
RED = ((255, 69, 58), (74, 28, 24))
YEL = ((255, 214, 10), (74, 62, 14))
GRN = ((48, 209, 88), (20, 64, 34))

R = 52                 # dot radius (doubled again for prominence)
GAP = 32               # gap between dots
PAD = 28               # padding around the dot column (room for glow)
TOP_MARGIN = 18        # vertical gap from the top edge (height unchanged)
LEFT_CM = 1.0          # horizontal gap from the LEFT edge, in centimeters
W = 2 * R + 2 * PAD
H = 3 * (2 * R) + 2 * GAP + 2 * PAD


def read_state():
    try:
        with open(STATE_FILE, "r") as f:
            s = f.read().strip()
        return s if s in ("busy", "wait", "done", "idle") else "idle"
    except OSError:
        return "idle"


class StatusLight(QtWidgets.QWidget):
    def __init__(self):
        super().__init__()
        self.state = None
        self.phase = 0
        self.done_flashes = 0
        self.wd_miss = 0       # consecutive watchdog misses
        self.colors = [RED[1], YEL[1], GRN[1]]   # current rgb per dot

        self.setWindowFlags(
            QtCore.Qt.FramelessWindowHint
            | QtCore.Qt.WindowStaysOnTopHint
            | QtCore.Qt.Tool                     # no taskbar entry
        )
        self.setAttribute(QtCore.Qt.WA_TranslucentBackground, True)
        self.setAttribute(QtCore.Qt.WA_ShowWithoutActivating, True)
        self.setFixedSize(W, H)
        self._place_top_left()

        self.timer = QtCore.QTimer(self)
        self.timer.timeout.connect(self.tick)
        self.timer.start(TICK_MS)
        self.apply_state(read_state(), force=True)

    def _place_top_left(self):
        app = QtWidgets.QApplication.instance()
        screen = app.primaryScreen()
        geo = screen.availableGeometry()
        # convert 1cm -> pixels using the screen's physical DPI (1in = 2.54cm)
        dpi = screen.physicalDotsPerInchX() or screen.logicalDotsPerInchX() or 96.0
        left_px = int(round(dpi / 2.54 * LEFT_CM))
        self.move(geo.x() + left_px, geo.y() + TOP_MARGIN)

    def apply_state(self, state, force=False):
        if state == self.state and not force:
            return
        self.state = state
        self.phase = 0
        self.done_flashes = 0

    def claude_alive(self):
        """True only if a REAL interactive Claude Code session is running.

        Claude Code's `claude.exe daemon run` keeps spare/forked sessions alive
        in the background after you close the window. Those have a pts terminal
        and innocuous-looking cmdlines, so the only reliable signal is ANCESTRY:
        a genuine session traces up to a shell/terminal, while a daemon-spawned
        one has `daemon run` somewhere in its parent chain. We exclude the
        latter by walking each candidate's parents.
        """
        try:
            cmd = {}        # pid -> cmdline string (claude procs + their parents)
            ppid = {}       # pid -> parent pid

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
                    if "daemon run" in cmd.get(cur, "") \
                            or "--bg-pty-host" in cmd.get(cur, "") \
                            or "--bg-spare" in cmd.get(cur, ""):
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
                        return True   # a real interactive session exists
                except OSError:
                    continue
            return False
        except OSError:
            return True  # never self-quit on a scan failure

    def tick(self):
        # watchdog: exit the light shortly after Claude Code is gone
        if self.phase % WATCHDOG_TICKS == 0:
            if self.claude_alive():
                self.wd_miss = 0
            else:
                self.wd_miss += 1
                if self.wd_miss >= WATCHDOG_MISSES:
                    QtWidgets.QApplication.quit()
                    return

        # periodically re-assert top-most so other windows can't cover it
        if self.phase % RAISE_TICKS == 0:
            self.raise_()

        current = read_state()
        if current != self.state:
            self.apply_state(current)

        if self.state == "busy":
            self.colors = [RED[1], YEL[0], GRN[1]]

        elif self.state == "wait":
            on = (self.phase // BLINK_TICKS) % 2 == 0
            self.colors = [RED[0] if on else RED[1], YEL[1], GRN[1]]

        elif self.state == "done":
            if self.done_flashes < DONE_FLASHES:
                on = (self.phase // DONE_BLINK_HALF) % 2 == 0
                self.colors = [RED[1], YEL[1], GRN[0] if on else GRN[1]]
                if self.phase > 0 and self.phase % (DONE_BLINK_HALF * 2) == 0:
                    self.done_flashes += 1
            else:
                self.colors = [RED[1], YEL[1], GRN[0]]

        else:  # idle
            self.colors = [RED[1], YEL[1], GRN[1]]

        self.phase += 1
        self.update()

    def paintEvent(self, _event):
        p = QtGui.QPainter(self)
        p.setRenderHint(QtGui.QPainter.Antialiasing, True)
        cx = PAD + R
        for i, (cr, cg, cb) in enumerate(self.colors):
            cy = PAD + R + i * (2 * R + GAP)
            base = QtGui.QColor(cr, cg, cb)
            # bright dots get a soft radial glow halo
            bright = (cr + cg + cb) > 320
            if bright:
                grad = QtGui.QRadialGradient(cx, cy, R + PAD)
                halo = QtGui.QColor(cr, cg, cb)
                halo.setAlpha(150)
                grad.setColorAt(0.55, halo)
                edge = QtGui.QColor(cr, cg, cb)
                edge.setAlpha(0)
                grad.setColorAt(1.0, edge)
                p.setPen(QtCore.Qt.NoPen)
                p.setBrush(QtGui.QBrush(grad))
                p.drawEllipse(QtCore.QPointF(cx, cy), R + PAD, R + PAD)
            # the dot itself
            p.setPen(QtCore.Qt.NoPen)
            p.setBrush(base)
            p.drawEllipse(QtCore.QPointF(cx, cy), R, R)
            # subtle highlight for a glossy bulb look
            if bright:
                hi = QtGui.QColor(255, 255, 255, 90)
                p.setBrush(hi)
                p.drawEllipse(QtCore.QPointF(cx - R * 0.3, cy - R * 0.3),
                              R * 0.35, R * 0.35)
        p.end()


def main():
    app = QtWidgets.QApplication([])
    w = StatusLight()
    w.show()
    app.exec()


if __name__ == "__main__":
    main()

