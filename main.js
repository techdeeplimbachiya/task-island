// Task Island — Electron main process (native desktop window, no browser, no internet).
// Inputs:
//   POST /event   Claude Code hook events            (integrations/claude)
//   POST /task    shell task start/output/end         (integrations/powershell, isl wrapper)
//   POST /ask     Yes/No question, held open until you answer (Claude permissions, isl -w prompts)
//   spool folder  JSON files dropped by the CMD/Clink script (no network calls from CMD)
//   helpers/notify-watch.ps1  mirrors Windows notifications from other apps
const { app, BrowserWindow, ipcMain, screen } = require('electron');
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');
const readline = require('readline');
const { spawn } = require('child_process');

// Only one island at a time: a second launch (startup shortcut + manual start) just exits quietly
if (!app.requestSingleInstanceLock()) app.exit(0);

const cfg = loadConfig();
const SPOOL = path.join(os.tmpdir(), 'claude-island', 'spool');
let win;
const pendingAsks = new Map(); // id -> held HTTP response

function loadConfig() {
  const defaults = { port: 47823, showAfterMs: 3000, toastMs: 6000, bannerMs: 5000, ignoreCommands: [],
    terminals: ['windowsterminal', 'powershell', 'pwsh', 'conhost', 'cmd.exe'],
    notifications: { enabled: true, pollMs: 1500, ignoreApps: [] } };
  try { return { ...defaults, ...JSON.parse(fs.readFileSync(path.join(__dirname, 'config.json'), 'utf8')) }; }
  catch { return defaults; }
}

function send(channel, data) {
  if (win && !win.isDestroyed()) win.webContents.send(channel, data);
}

function createWindow() {
  const { width } = screen.getPrimaryDisplay().workAreaSize;
  const W = 480, H = 200;
  win = new BrowserWindow({
    width: W, height: H, x: Math.round((width - W) / 2), y: 6,
    frame: false, transparent: true, resizable: false, movable: false,
    alwaysOnTop: true, skipTaskbar: true, hasShadow: false,
    webPreferences: { preload: path.join(__dirname, 'preload.js') },
  });
  win.setAlwaysOnTop(true, 'screen-saver');
  win.setIgnoreMouseEvents(true, { forward: true }); // click-through except over the pill
  win.loadFile('index.html');
  win.webContents.on('did-finish-load', () => send('config', cfg));
}

// ---------- local HTTP server (127.0.0.1 only) ----------
function startServer() {
  http.createServer((req, res) => {
    if (req.method !== 'POST') { res.statusCode = 404; return res.end(); }
    let body = '';
    req.on('data', c => { body += c; if (body.length > 1e6) req.destroy(); });
    req.on('end', () => {
      let msg;
      try { msg = JSON.parse(body); } catch { res.statusCode = 400; return res.end(); }
      switch (req.url) {
        case '/event': send('claude', msg); return res.end('ok');
        case '/task':  send('task', msg);   return res.end('ok');
        case '/ask': {
          const id = `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
          pendingAsks.set(id, res);
          res.on('close', () => { if (pendingAsks.delete(id)) send('ask-cancel', { id }); });
          return send('ask', { id, ...msg });
        }
        default: res.statusCode = 404; res.end();
      }
    });
  }).on('error', err => {
    // Port taken (another island, or another app): log it instead of crashing with a popup
    console.error(`Task Island could not use port ${cfg.port}: ${err.code}`);
  }).listen(cfg.port, '127.0.0.1', () => console.log(`Task Island on 127.0.0.1:${cfg.port}`));
}

ipcMain.on('answer', (_e, { id, answer }) => {
  const res = pendingAsks.get(id);
  if (!res) return;
  pendingAsks.delete(id);
  res.end(JSON.stringify({ answer })); // "yes" | "no"
});
ipcMain.on('clickable', (_e, on) => win && win.setIgnoreMouseEvents(!on, { forward: true }));

// ---------- spool folder for CMD (Clink) ----------
function startSpool() {
  fs.mkdirSync(SPOOL, { recursive: true });
  const drain = () => {
    let files;
    try { files = fs.readdirSync(SPOOL).filter(f => f.endsWith('.json')).sort(); } catch { return; }
    for (const f of files) {
      const p = path.join(SPOOL, f);
      try { const msg = JSON.parse(fs.readFileSync(p, 'utf8')); fs.unlinkSync(p); send('task', msg); }
      catch { try { fs.unlinkSync(p); } catch {} }
    }
  };
  try { fs.watch(SPOOL, drain); } catch {}
  setInterval(drain, 1000); // fallback if watch events are missed
}

// ---------- Windows notification mirror ----------
function startNotificationWatcher() {
  if (process.platform !== 'win32' || !cfg.notifications.enabled) return;
  const base = app.isPackaged ? process.resourcesPath : __dirname;
  const script = path.join(base, 'helpers', 'notify-watch.ps1');
  const ps = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', script, '-PollMs', String(cfg.notifications.pollMs)], { windowsHide: true });
  const ignore = (cfg.notifications.ignoreApps || []).map(s => s.toLowerCase());
  readline.createInterface({ input: ps.stdout }).on('line', line => {
    let n; try { n = JSON.parse(line); } catch { return; }
    if (ignore.some(a => (n.app || '').toLowerCase().includes(a))) return;
    send('notification', n);
  });
  ps.stderr.on('data', d => console.error('[notify]', d.toString().trim()));
  ps.on('exit', () => setTimeout(startNotificationWatcher, 5000)); // restart if it dies
}

// ---------- is a terminal the focused window? (optional) ----------
async function watchFocus() {
  let activeWindow;
  try { ({ activeWindow } = await import('get-windows')); }
  catch { console.log('get-windows not installed: island stays visible while tasks run'); return; }
  let last = null;
  setInterval(async () => {
    try {
      const w = await activeWindow();
      const name = (w?.owner?.path || w?.owner?.name || '').toLowerCase();
      const focused = cfg.terminals.some(t => name.includes(t));
      if (focused !== last) { last = focused; send('terminal-focus', focused); }
    } catch {}
  }, 700);
}

app.whenReady().then(() => {
  createWindow(); startServer(); startSpool(); startNotificationWatcher(); watchFocus();
});
app.on('window-all-closed', () => app.quit());
