# Claude Code StatusLight

A desktop traffic-light indicator that shows Claude Code's real-time status — always visible, always on top.

```
🔴 ── Red (blinking)  = Needs your permission
🟡 ── Yellow (solid)  = Thinking / running
🟢 ── Green (flash x6 then solid) = Task complete
```

The three colored dots float at the top-left of your screen, **above all other windows** — even full-screen browsers and IDEs. They appear when Claude Code starts and disappear when it exits.

## How It Works

```
Claude Code hooks  ──write──▶  state file (busy|wait|done|idle)
watchdog.py        ──write──▶  alive heartbeat (timestamp)

PowerShell/WPF     ──reads──▶  both files, renders 3 dots
(always-on-top)
```

- **Hook scripts are async and timeout-protected** — they can never block Claude Code.
- **Watchdog detects real Claude sessions** via `/proc` ancestry — the light shuts off when you close Claude.
- **WPF native window** renders true transparent, always-on-top dots on Windows.

## Requirements

- **Windows 10/11** with **WSL2**
- **WSLg** enabled
- **Claude Code** installed in WSL
- Python 3 (stdlib only — no extra packages needed)

## Quick Start

### 1. Install

```bash
git clone https://github.com/YOUR_USERNAME/cc-statuslight.git ~/.claude/statuslight
```

### 2. Register Claude Code hooks

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "matcher": "", "hooks": [
        { "type": "command", "command": "~/.claude/statuslight/set-state.sh busy", "async": true, "timeout": 5 }
      ]}
    ],
    "PreToolUse": [
      { "matcher": "", "hooks": [
        { "type": "command", "command": "~/.claude/statuslight/set-state.sh busy", "async": true, "timeout": 5 }
      ]}
    ],
    "Notification": [
      { "matcher": "permission_prompt", "hooks": [
        { "type": "command", "command": "~/.claude/statuslight/set-state.sh wait", "async": true, "timeout": 5 }
      ]}
    ],
    "Stop": [
      { "matcher": "", "hooks": [
        { "type": "command", "command": "~/.claude/statuslight/set-state.sh done", "async": true, "timeout": 5 }
      ]}
    ],
    "SessionStart": [
      { "matcher": "", "hooks": [
        { "type": "command", "command": "~/.claude/statuslight/set-state.sh idle", "async": true, "timeout": 5 },
        { "type": "command", "command": "~/.claude/statuslight/launch.sh", "async": true, "timeout": 10 }
      ]}
    ],
    "SessionEnd": [
      { "matcher": "", "hooks": [
        { "type": "command", "command": "~/.claude/statuslight/launch.sh stop", "async": true, "timeout": 10 }
      ]}
    ]
  }
}
```

### 3. Restart Claude Code

Close and reopen Claude Code — three dots appear at the top-left of your screen.

## Manual Control

```bash
~/.claude/statuslight/launch.sh          # start the display
~/.claude/statuslight/launch.sh stop     # stop everything

# Test states manually:
~/.claude/statuslight/set-state.sh busy   # yellow solid
~/.claude/statuslight/set-state.sh wait   # red blinking
~/.claude/statuslight/set-state.sh done   # green flash x6
~/.claude/statuslight/set-state.sh idle   # all dim
```

## State Reference

| State | Red (top) | Yellow (middle) | Green (bottom) | Meaning |
|-------|-----------|-----------------|----------------|---------|
| `idle` | dim | dim | dim | Waiting for input |
| `busy` | dim | **bright** | dim | Claude is thinking |
| `wait` | **blinking** | dim | dim | Needs permission |
| `done` | dim | dim | **flash x6 then solid** | Task complete |

## Files

| File | Role | Runtime |
|------|------|---------|
| `set-state.sh` | Hook entry — atomic write to state file | WSL |
| `watchdog.py` | Liveness detection — writes heartbeat, exits when Claude is gone | WSL |
| `statuslight.ps1` | WPF display — renders three dots, always on top | Windows |
| `launch.sh` | Lifecycle manager — start/stop watchdog + display | WSL |
| `xcblibs/` | XCB helper libraries for WSLg compatibility | WSL |

## Architecture Decisions

### Why Windows native (WPF) instead of WSLg GTK/Qt?
WSLg's `_NET_WM_STATE_ABOVE` only works among WSLg windows — a browser or VS Code will cover a WSLg window. WPF's `TopMost = $true` is true Windows always-on-top.

### Why `/proc` ancestry detection instead of `pgrep`?
Claude Code keeps a `daemon run` background process with spare sessions. Simple `pgrep -f claude` would match these forever. The watchdog walks the parent chain to exclude daemon-spawned processes.

### Why async hooks?
All status-light hooks use `"async": true` with a 5–10s timeout — they can never slow down or hang Claude Code.

## License

MIT — see [LICENSE](LICENSE).
