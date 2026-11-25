# Task Island integration for PowerShell (5.1 and 7+).
# Tracks EVERY command you run. The island only shows commands that run longer
# than "showAfterMs" (config.json), so quick commands never flash.
#
# Installed automatically by install.ps1. Manual install: add this line at the END of your $PROFILE
#   . "<repo folder>\integrations\powershell\island.ps1"

Add-Type -AssemblyName System.Net.Http

$global:__Island = @{
  Url     = 'http://127.0.0.1:47823/task'
  Client  = [System.Net.Http.HttpClient]::new()
  Current = $null
}
$global:__Island.Client.Timeout = [TimeSpan]::FromSeconds(2)

function global:__IslandSend([hashtable]$Data) {
  # Fire-and-forget: never slows the prompt, silently ignored if the island isn't running
  try {
    $json = $Data | ConvertTo-Json -Compress
    $content = [System.Net.Http.StringContent]::new($json, [Text.Encoding]::UTF8, 'application/json')
    [void]$global:__Island.Client.PostAsync($global:__Island.Url, $content)
  } catch {}
}

# Command START: hook the Enter key
Set-PSReadLineKeyHandler -Key Enter -ScriptBlock {
  $line = $null; $cursor = $null
  [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
  if ($line -and $line.Trim()) {
    $id = "pwsh-$PID-$([DateTime]::Now.Ticks)"
    $global:__Island.Current = $id
    __IslandSend @{ phase = 'start'; id = $id; source = 'pwsh'; command = $line.Trim();
                    cwd = (Get-Location).Path; pid = $PID }
  }
  [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

# Command END: wrap the prompt (runs right after each command finishes)
$global:__IslandOrigPrompt = $function:prompt
function global:prompt {
  $ok = $?                         # must be the first statement
  $code = $global:LASTEXITCODE
  if ($global:__Island.Current) {
    __IslandSend @{ phase = 'end'; id = $global:__Island.Current; ok = $ok; exitCode = $(if ($ok) { 0 } else { $code }) }
    $global:__Island.Current = $null
  }
  & $global:__IslandOrigPrompt
}
