# Removes everything install.ps1 set up. Run from the repo folder:
#   powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
# Then delete the folder. Your script policy setting is left as it is.
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot

Get-Process electron -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$root\*" } | Stop-Process -Force

$docs = [Environment]::GetFolderPath('MyDocuments')
foreach ($p in "$docs\WindowsPowerShell\Microsoft.PowerShell_profile.ps1", "$docs\PowerShell\Microsoft.PowerShell_profile.ps1") {
  if (Test-Path $p) {
    $lines = @(Get-Content $p | Where-Object { $_ -notmatch 'integrations\\powershell\\island\.ps1' })
    Set-Content -Path $p -Value $lines -Encoding UTF8
  }
}

if (Get-Command node -ErrorAction SilentlyContinue) { node "$root\scripts\claude-hooks.js" uninstall }

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$parts = @(($userPath -split ';') | Where-Object { $_ -and $_ -notmatch 'integrations\\cmd$' })
[Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')

$startup = [Environment]::GetFolderPath('Startup')
$shell = New-Object -ComObject WScript.Shell
Get-ChildItem $startup -Filter *.lnk | ForEach-Object {
  $sc = $shell.CreateShortcut($_.FullName)
  if ("$($sc.TargetPath) $($sc.Arguments)" -match 'start-island\.vbs|task-island') { Remove-Item $_.FullName -Force }
}

Write-Host 'Task Island removed. You can now delete this folder.' -ForegroundColor Green
