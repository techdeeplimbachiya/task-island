# Task Island

A Dynamic-Island style bar at the top of your **Windows** screen for everything running in the background.

- **Any PowerShell command**: long commands show a live timer, then ✓ Finished or ✕ Failed (exit code)
- **Claude Code**: live steps, plus **Deny / Allow once / Always allow** permission prompts answered from the bar
- **CMD**: prefix any command with `isl`, or track everything automatically with Clink
- **Yes/No prompts from any CLI** (`[Y/n]`, `(yes/no)`, `Continue?`) with `isl -w`
- **Windows notifications** from other apps (Outlook, Teams, WhatsApp, Chrome…), mirrored into the bar

Native desktop app (Electron, no browser tab). **Runs 100% offline**: everything stays on `127.0.0.1`.
Internet is needed only once, to download Electron during install.

> Open `index.html` in a browser to see a demo of every state.

## Install

Requirements: Windows 10/11 and [Node.js 18+](https://nodejs.org).

```powershell
git clone https://github.com/techdeeplimbachiya/task-island.git
cd task-island
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

**Or let Claude do it:** open `claude` inside the cloned folder and say *"install this"*.
`CLAUDE.md` tells it how.

The installer:
1. runs `npm install`
2. adds one line to your PowerShell profile (tracks every command)
3. merges the Claude Code hooks into `~/.claude/settings.json` (your other settings are kept; a backup is saved)
4. adds the `isl` command to your PATH
5. creates a Startup shortcut so the island launches hidden at every login, and starts it now

Then open a **new** terminal (and restart `claude`) and try `Start-Sleep 10`, then switch to another window.

Skip parts with `-SkipClaude`, `-SkipPowerShell`, `-SkipStartup`, `-SkipIslPath`.
Re-run the installer any time after `git pull` or after moving the folder.

**Uninstall:** `powershell -ExecutionPolicy Bypass -File .\uninstall.ps1`, then delete the folder.

## Using it

| Where | What happens |
|---|---|
| PowerShell | Automatic. Commands under 3 s never show. Interactive ones (`claude`, `vim`, `ssh`…) are skipped |
| Claude Code | Automatic. Hover the pill for the last steps. Permission asks show on the island and in the terminal; answer in either |
| CMD | `isl npm run build`, or `isl -w <cmd>` to also see the latest output line and answer Y/N prompts |
| CMD (automatic) | Install [Clink](https://chrisant996.github.io/clink/), run `clink info`, copy `integrations\cmd\island.lua` into its scripts folder |
| Notifications | Automatic. Click a toast to dismiss it |

Priority on the bar: question → notification → finished/failed banner → running tasks.
With the optional `get-windows` package, task status hides while a terminal is focused, so it appears only when you've switched away.

Settings live in `config.json`: `showAfterMs`, `ignoreCommands`, `notifications.ignoreApps`, `notifications.enabled`.

## How it works

```
PowerShell profile ──HTTP──┐
isl wrapper ─────────HTTP──┤
Claude Code hooks ───HTTP──┤──►  main.js (Electron, 127.0.0.1:47823) ──IPC──► index.html (the island)
CMD + Clink ──JSON files───┤        ▲   └── answers go back over the held HTTP request
notify-watch.ps1 ──stdout──┘        └── reads Windows' local notification DB via built-in winsqlite3.dll
```

## Troubleshooting

| Problem | Fix |
|---|---|
| "not digitally signed" / "running scripts is disabled" | `Get-ChildItem . -Recurse \| Unblock-File`, then `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| `'electron' is not recognized` | `npm install` didn't finish: run it again in the folder |
| `EADDRINUSE 127.0.0.1:47823` popup | Two copies started: end `electron` in Task Manager, then double-click `start-island.vbs` |
| Claude shows nothing | Restart `claude`; type `/hooks` to check the hooks are listed |
| settings.json "malformed JSON" | Your file had a JSON error before install: fix it, then run `node scripts/claude-hooks.js install` |

## Limits

- Plain PowerShell/CMD tracking sees start, end, and exit code, not the output. Use `isl -w` for output and prompts.
- `isl -w` pipes output, so some tools drop colours or progress bars in that mode.
- Notification mirroring reads an undocumented Windows database. A Windows update could break it; the rest keeps working.
- "Always allow" applies the rule Claude Code suggests for its own "don't ask again" option. It never changes your permission mode.

## Portable .exe

`npm run dist` builds `dist\Task Island.exe` (downloads electron-builder on first use).

## Project layout

| Path | Role |
|---|---|
| `main.js` / `preload.js` / `index.html` | The app: window, local server, UI |
| `config.json` | Thresholds, ignored commands, notification filters |
| `install.ps1` / `uninstall.ps1` / `start-island.vbs` | Setup, removal, hidden launcher |
| `scripts/claude-hooks.js` | Safely adds/removes hooks in Claude settings |
| `helpers/notify-watch.ps1` | Windows notification mirror |
| `integrations/claude` | Claude Code hook |
| `integrations/powershell` | Profile script |
| `integrations/cmd` | `isl` wrapper and Clink script |

MIT License
