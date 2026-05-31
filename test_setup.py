#!/usr/bin/env python3
"""One-shot: clean, start watchdog, test PowerShell connectivity."""
import subprocess, os, time, signal

d = os.path.dirname(os.path.abspath(__file__))
py = os.path.join(d, "venv/bin/python")

# 1) Kill old
for pat in ["watchdog.py", "statuslight"]:
    r = subprocess.run(["pgrep", "-f", pat], capture_output=True, text=True)
    for pid in r.stdout.split():
        try: os.kill(int(pid), signal.SIGKILL)
        except: pass
time.sleep(1)
for f in ["alive", ".gui.pid", ".launcher.pid"]:
    try: os.remove(os.path.join(d, f))
    except: pass
print("1. cleaned")

# 2) Watchdog
p = subprocess.Popen([py, os.path.join(d, "watchdog.py")],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print(f"2. watchdog pid={p.pid}")
time.sleep(4)
af = os.path.join(d, "alive")
print(f"3. alive={'OK:'+open(af).read().strip() if os.path.exists(af) else 'MISSING'}")

# 3) PS read test
ps1 = r"\\wsl.localhost\Ubuntu\home\dys07\.claude\statuslight\statuslight.ps1"
r = subprocess.run(["powershell.exe", "-NoProfile", "-Command",
    f"$c=Get-Content -Raw '{ps1}';Write-Host 'PS1 read OK len='$c.Length"],
    capture_output=True, text=True, timeout=15)
print(f"4. PS read: {r.stdout.strip()[:120]} {r.stderr.strip()[:120]}")
