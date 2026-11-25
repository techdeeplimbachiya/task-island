# Task Island: notes for Claude Code

Task Island is a Windows-only Electron app: a Dynamic-Island style bar at the top of the screen that
shows background PowerShell/CMD tasks and Claude Code activity, lets the user answer Claude permission
prompts from the bar, and mirrors Windows notifications. Everything runs locally (127.0.0.1:47823).

## If the user asks you to install it

1. Confirm this is Windows and `node -v` is 18 or newer. If Node is missing, tell the user to install
   the LTS from https://nodejs.org (or `winget install OpenJS.NodeJS.LTS`) and open a new terminal.
2. From the repo root, run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1`
   The script is idempotent. It installs npm packages, adds the PowerShell profile line, merges the
   Claude Code hooks into `~/.claude/settings.json` (backup saved as `settings.json.task-island.bak`),
   puts `isl` on the user PATH, creates a Startup shortcut, and starts the island.
   It edits the user's global Claude settings and shell profile, so tell the user what it will change
   and get their OK before running it.
3. Tell the user to open a new terminal and restart `claude` (hooks load at startup), then test with
   `Start-Sleep 10` while switching to another window.

Flags: `-SkipClaude`, `-SkipPowerShell`, `-SkipStartup`, `-SkipIslPath`.
To remove: `powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1`.

## Troubleshooting

- "not digitally signed" / "running scripts is disabled": run
  `Get-ChildItem <repo> -Recurse | Unblock-File` and `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.
- `'electron' is not recognized`: `npm install` didn't finish. Run it again in the repo root.
- `EADDRINUSE 127.0.0.1:47823`: another copy is running. End `electron` processes and start
  `start-island.vbs` again.
- settings.json "Invalid or malformed JSON": the user's file was broken before. Fix the JSON, then rerun
  `node scripts/claude-hooks.js install`.

## Layout

- `main.js`: window, local HTTP server (`/event`, `/task`, `/ask`), CMD spool folder, notification watcher
- `index.html`: the island UI (opens in a browser as a demo)
- `integrations/`: claude hook, PowerShell profile script, CMD `isl` wrapper and Clink script
- `helpers/notify-watch.ps1`: reads Windows' notification DB through the built-in winsqlite3.dll
- `scripts/claude-hooks.js`: safe merge/unmerge of hooks into Claude settings
