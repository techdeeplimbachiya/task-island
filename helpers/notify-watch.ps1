# Mirrors Windows notifications (Teams, Outlook, WhatsApp, Chrome, system...) to Task Island.
# Reads Windows' own local notification database read-only using the SQLite engine that ships
# with Windows (winsqlite3.dll). Fully offline, no install, no admin rights.
# Prints one JSON line per new notification on stdout: {"app":..,"title":..,"body":..}
# Note: the database format is undocumented by Microsoft and could change in a future Windows update.
param([int]$PollMs = 1500)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public class NotifRow { public long Id; public string App; public string Payload; }

public static class WpnReader {
    const string L = "winsqlite3.dll";
    [DllImport(L)] static extern int sqlite3_open_v2(byte[] file, out IntPtr db, int flags, IntPtr vfs);
    [DllImport(L)] static extern int sqlite3_close(IntPtr db);
    [DllImport(L)] static extern int sqlite3_busy_timeout(IntPtr db, int ms);
    [DllImport(L)] static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int n, out IntPtr stmt, IntPtr tail);
    [DllImport(L)] static extern int sqlite3_bind_int64(IntPtr stmt, int i, long v);
    [DllImport(L)] static extern int sqlite3_step(IntPtr stmt);
    [DllImport(L)] static extern int sqlite3_finalize(IntPtr stmt);
    [DllImport(L)] static extern long sqlite3_column_int64(IntPtr stmt, int i);
    [DllImport(L)] static extern IntPtr sqlite3_column_blob(IntPtr stmt, int i);
    [DllImport(L)] static extern int sqlite3_column_bytes(IntPtr stmt, int i);

    const int SQLITE_ROW = 100, SQLITE_OPEN_READONLY = 1;

    static byte[] Z(string s) { return Encoding.UTF8.GetBytes(s + "\0"); }

    static string Col(IntPtr st, int i) {
        int n = sqlite3_column_bytes(st, i);
        IntPtr p = sqlite3_column_blob(st, i);
        if (p == IntPtr.Zero || n <= 0) return "";
        byte[] b = new byte[n];
        Marshal.Copy(p, b, 0, n);
        return Encoding.UTF8.GetString(b);
    }

    public static List<NotifRow> Since(string path, long lastId) {
        var rows = new List<NotifRow>();
        IntPtr db;
        if (sqlite3_open_v2(Z(path), out db, SQLITE_OPEN_READONLY, IntPtr.Zero) != 0) {
            sqlite3_close(db); throw new Exception("cannot open " + path);
        }
        try {
            sqlite3_busy_timeout(db, 500);
            string sql = "SELECT n.Id, h.PrimaryId, n.Payload FROM Notification n " +
                         "JOIN NotificationHandler h ON h.RecordId = n.HandlerId " +
                         "WHERE n.Type = 'toast' AND n.Id > ?1 ORDER BY n.Id";
            IntPtr st;
            if (sqlite3_prepare_v2(db, Z(sql), -1, out st, IntPtr.Zero) != 0) throw new Exception("prepare failed");
            try {
                sqlite3_bind_int64(st, 1, lastId);
                while (sqlite3_step(st) == SQLITE_ROW)
                    rows.Add(new NotifRow { Id = sqlite3_column_int64(st, 0), App = Col(st, 1), Payload = Col(st, 2) });
            } finally { sqlite3_finalize(st); }
        } finally { sqlite3_close(db); }
        return rows;
    }
}
'@

$db = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Notifications\wpndatabase.db'
if (-not (Test-Path $db)) { [Console]::Error.WriteLine("notification database not found: $db"); exit 1 }

function Get-Rows([long]$after) {
  try { return ,([WpnReader]::Since($db, $after)) }
  catch {
    # If the live file is locked, read a fresh copy (db + its WAL/SHM side files) instead
    $tmp = Join-Path $env:TEMP 'claude-island'
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    foreach ($ext in '', '-wal', '-shm') {
      if (Test-Path "$db$ext") { Copy-Item "$db$ext" (Join-Path $tmp "wpn.db$ext") -Force }
    }
    return ,([WpnReader]::Since((Join-Path $tmp 'wpn.db'), $after))
  }
}

function Get-AppName([string]$primaryId) {
  # "Microsoft.Teams_8wekyb3d8bbwe!MSTeams" -> "Teams";  "C:\...\chrome.exe" -> "chrome"
  $s = $primaryId
  if ($s -match '[\\/]') { return [IO.Path]::GetFileNameWithoutExtension($s) }
  $s = ($s -split '!')[0]; $s = ($s -split '_')[0]
  return ($s -split '\.')[-1]
}

# Start from the newest existing notification so old ones aren't replayed
$last = 0L
try { $rows = Get-Rows 0; if ($rows.Count) { $last = [long](($rows | Measure-Object Id -Maximum).Maximum) } } catch {}

while ($true) {
  Start-Sleep -Milliseconds $PollMs
  try { $rows = Get-Rows $last } catch { continue }
  foreach ($r in $rows) {
    if ($r.Id -gt $last) { $last = $r.Id }
    try { [xml]$x = $r.Payload } catch { continue }
    $texts = @($x.SelectNodes('//text') | ForEach-Object { $_.InnerText.Trim() } | Where-Object { $_ })
    if ($texts.Count -eq 0) { continue }
    $out = [ordered]@{
      app   = Get-AppName $r.App
      title = $texts[0]
      body  = ($texts | Select-Object -Skip 1) -join ' '
    }
    [Console]::Out.WriteLine(($out | ConvertTo-Json -Compress))
    [Console]::Out.Flush()
  }
}
