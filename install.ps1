# Task Island installer for Windows. Run from the repo folder:
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
# Options: -SkipClaude  -SkipPowerShell  -SkipStartup  -SkipIslPath
# Safe to run again (after a git pull, or if you moved the folder): it replaces its own old settings.
param([switch]$SkipClaude, [switch]$SkipPowerShell, [switch]$SkipStartup, [switch]$SkipIslPath)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
function Step($m) { Write-Host "`n> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  OK  $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  !!  $m" -ForegroundColor Yellow }

Step 'Checking Node.js'
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  throw 'Node.js 18 or newer is required. Install the LTS from https://nodejs.org (or run: winget install OpenJS.NodeJS.LTS), open a new terminal, and run this again.'
}
$nodeVer = [version]((node -v).Trim().TrimStart('v'))
if ($nodeVer.Major -lt 18) { throw "Node.js 18 or newer is required (found $nodeVer)." }
Ok "Node $nodeVer"

Step 'Unblocking downloaded files'
Get-ChildItem $root -Recurse -File | Where-Object { $_.FullName -notmatch '\\node_modules\\' } | Unblock-File
Ok 'done'

Step 'Installing dependencies (one-time Electron download, about a minute)'
Push-Location $root
try {
  npm install --no-fund --no-audit
  if ($LASTEXITCODE -ne 0) { throw 'npm install failed. See the messages above.' }
} finally { Pop-Location }
Ok 'done'

if (-not $SkipPowerShell) {
  Step 'PowerShell: track every command'
  if ((Get-ExecutionPolicy -Scope CurrentUser) -in 'Undefined', 'Restricted', 'AllSigned') {
    try { Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force; Ok 'Script policy for your user set to RemoteSigned' }
    catch { Warn "Could not change the script policy (it may be set by your organization): $($_.Exception.Message)" }
  }
  $docs = [Environment]::GetFolderPath('MyDocuments')
  $profiles = @("$docs\WindowsPowerShell\Microsoft.PowerShell_profile.ps1")
  if (Get-Command pwsh -ErrorAction SilentlyContinue) { $profiles += "$docs\PowerShell\Microsoft.PowerShell_profile.ps1" }
  $line = ". `"$root\integrations\powershell\island.ps1`"  # task-island"
  foreach ($p in $profiles) {
    if (-not (Test-Path $p)) { New-Item -ItemType File -Force -Path $p | Out-Null }
    $lines = @(Get-Content $p -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch 'integrations\\powershell\\island\.ps1' })
    Set-Content -Path $p -Value ($lines + $line) -Encoding UTF8
    Ok "Added to $p"
  }
}

if (-not $SkipClaude) {
  Step 'Claude Code: live steps + Allow/Deny from the island'
  node "$root\scripts\claude-hooks.js" install
  if ($LASTEXITCODE -ne 0) { Warn 'Claude hooks were not added (see above). Everything else still works.' }
}

if (-not $SkipIslPath) {
  Step "CMD: add the 'isl' command to your PATH"
  $islDir = "$root\integrations\cmd"
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  $parts = @(($userPath -split ';') | Where-Object { $_ -and $_ -notmatch 'integrations\\cmd$' })
  [Environment]::SetEnvironmentVariable('Path', (($parts + $islDir) -join ';'), 'User')
  Ok "Added $islDir (new terminals only)"
}

if (-not $SkipStartup) {
  Step 'Start automatically when you log in'
  $startup = [Environment]::GetFolderPath('Startup')
  $shell = New-Object -ComObject WScript.Shell
  Get-ChildItem $startup -Filter *.lnk | ForEach-Object {
    $sc = $shell.CreateShortcut($_.FullName)
    if ("$($sc.TargetPath) $($sc.Arguments)" -match 'start-island\.vbs|task-island') { Remove-Item $_.FullName -Force }
  }
  $lnk = $shell.CreateShortcut("$startup\Task Island.lnk")
  $lnk.TargetPath = "$root\start-island.vbs"
  $lnk.WorkingDirectory = $root
  $lnk.Save()
  Ok 'Startup shortcut created'
}

Step 'Starting Task Island'
Get-Process electron -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$root\*" } | Stop-Process -Force
Start-Sleep -Milliseconds 500
Start-Process wscript.exe "`"$root\start-island.vbs`""
Ok 'Running in the background'

Write-Host "`nDone. Open a NEW terminal (and restart 'claude' if it's open) to use it." -ForegroundColor Green
Write-Host "Quick test: run  Start-Sleep 10  and switch to another window."
Write-Host "Optional: for automatic CMD tracking, install Clink and copy integrations\cmd\island.lua into its scripts folder."
