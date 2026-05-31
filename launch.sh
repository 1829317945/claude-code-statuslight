#!/usr/bin/env bash
# Launcher for the Claude Code status light.
#   launch.sh         -> start watchdog + Windows display (no-op if already up)
#   launch.sh stop    -> stop everything
#   launch.sh restart -> stop then start
#
# Uses PID files to reliably track running state — avoids pgrep false positives.
set -uo pipefail

dir="${HOME}/.claude/statuslight"
py="${dir}/venv/bin/python"
watchdog="${dir}/watchdog.py"
ps1="${dir}/statuslight.ps1"
pidfile_wd="${dir}/.watchdog.pid"
pidfile_ps="${dir}/.ps-display.pid"

# auto-detect WSL distro name; fall back to "Ubuntu"
wsl_distro="${WSL_DISTRO_NAME:-}"
if [ -z "$wsl_distro" ]; then
  wsl_distro="$(wslpath -m / 2>/dev/null | sed 's|^//wsl\.localhost/||;s|/.*||' || true)"
fi
wsl_distro="${wsl_distro:-Ubuntu}"
wsl_path="\\\\wsl.localhost\\${wsl_distro}\\home\\${USER}\\.claude\\statuslight\\statuslight.ps1"

# Check if a PID is alive
alive() { kill -0 "$1" 2>/dev/null; }

# Check if the Windows statuslight display is running (by PID file)
ps_running() {
  [ -f "$pidfile_ps" ] && alive "$(cat "$pidfile_ps")"
}

# Check if watchdog is running (by PID file)
wd_running() {
  [ -f "$pidfile_wd" ] && alive "$(cat "$pidfile_wd")"
}

stop() {
  # 1) kill powershell display
  if [ -f "$pidfile_ps" ]; then
    local pspid
    pspid=$(cat "$pidfile_ps")
    kill "$pspid" 2>/dev/null || true
    sleep 0.5
    kill -9 "$pspid" 2>/dev/null || true
    rm -f "$pidfile_ps"
  fi
  # fallback: kill any remaining powershell running our script
  pkill -f 'powershell.*statuslight\.ps1' 2>/dev/null || true

  # 2) kill watchdog
  if [ -f "$pidfile_wd" ]; then
    local wpid
    wpid=$(cat "$pidfile_wd")
    kill "$wpid" 2>/dev/null || true
    sleep 0.5
    kill -9 "$wpid" 2>/dev/null || true
    rm -f "$pidfile_wd"
  fi
  pkill -f "venv/bin/python.*watchdog\.py" 2>/dev/null || true

  rm -f "${dir}/alive"
}

start() {
  # 1) watchdog (WSL, checks /proc ancestry)
  if ! wd_running; then
    rm -f "$pidfile_wd"
    nohup "$py" "$watchdog" > "${dir}/watchdog.log" 2>&1 &
    echo $! > "$pidfile_wd"
  fi

  # 2) Windows WPF always-on-top display
  if ps_running; then
    return 0   # already up
  fi
  rm -f "$pidfile_ps"

  # Launch via nohup so it survives hook timeout.
  # Use -File (not -Command + Invoke-Expression) — direct script execution is reliable.
  nohup powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden \
    -File "${wsl_path}" \
    > "${dir}/ps-launch.log" 2>&1 &
  local ps_pid=$!
  echo "$ps_pid" > "$pidfile_ps"
  disown
}

case "${1:-start}" in
  stop)    stop ;;
  restart) stop; sleep 1; start ;;
  start|*) start ;;
esac
