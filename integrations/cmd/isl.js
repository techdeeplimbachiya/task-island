#!/usr/bin/env node
// isl — run any command and track it on Task Island. Works in CMD and PowerShell.
//   isl npm run build          normal mode: full terminal colours/progress bars; island shows timer + done/failed
//   isl -w winget upgrade --all watch mode: island also shows the latest output line and catches
//                               Yes/No prompts like "[Y/n]" so you can answer from the island
const { spawn } = require('child_process');
const http = require('http');

const PORT = 47823;
const PROMPT_RE = /(\[y\/n\]|\(y\/n\)|\[y\/n\/a\]|\(yes\/no\)|\[yes\/no\]|\by\/n\s*[:?]?\s*$|continue\?\s*$|proceed\?\s*$|are you sure.*\?\s*$)/i;
const ANSI_RE = /\x1b\[[0-9;?]*[ -\/]*[@-~]|\x1b\][^\x07]*\x07/g;

const args = process.argv.slice(2);
let watch = false;
if (args[0] === '-w') { watch = true; args.shift(); }
if (!args.length) { console.error('usage: isl [-w] <command ...>'); process.exit(1); }

const command = args.join(' ');
const id = `isl-${process.pid}-${Date.now()}`;

function post(route, data, timeoutMs = 1500, onReq) {
  return new Promise(resolve => {
    const body = JSON.stringify(data);
    const req = http.request({
      host: '127.0.0.1', port: PORT, path: route, method: 'POST', timeout: timeoutMs,
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
    }, res => { let out = ''; res.on('data', c => (out += c)); res.on('end', () => resolve(out)); });
    req.on('error', () => resolve(null));
    req.on('timeout', () => { req.destroy(); resolve(null); });
    if (onReq) onReq(req);
    req.end(body);
  });
}

post('/task', { phase: 'start', id, source: 'isl', command, cwd: process.cwd(), pid: process.pid });

const child = spawn(command, { shell: true, stdio: watch ? ['pipe', 'pipe', 'pipe'] : 'inherit' });

if (watch) {
  let tail = '', lastSent = 0, idle, askReq = null;
  const clean = s => s.replace(ANSI_RE, '');

  const onData = out => buf => {
    out.write(buf);
    if (askReq) { askReq.destroy(); askReq = null; } // new output: prompt was answered in the terminal
    tail = (tail + buf.toString()).slice(-2000);
    const last = clean(tail).split(/\r?\n|\r/).filter(l => l.trim()).pop() || '';
    if (last && Date.now() - lastSent > 700) {
      lastSent = Date.now();
      post('/task', { phase: 'output', id, line: last.trim().slice(0, 160) });
    }
    clearTimeout(idle);
    idle = setTimeout(checkPrompt, 350); // output paused — is it waiting for an answer?
  };

  async function checkPrompt() {
    const partial = clean(tail).split(/\r?\n/).pop().trim(); // last line without a newline yet
    if (!partial || !PROMPT_RE.test(partial)) return;
    const long = /yes\/no/i.test(partial);
    const out = await post('/ask', { source: 'isl', title: 'Answer needed', project: command, detail: partial },
      110_000, r => (askReq = r));
    askReq = null;
    let answer; try { answer = JSON.parse(out).answer; } catch { return; }
    const text = answer === 'yes' ? (long ? 'yes' : 'y') : (long ? 'no' : 'n');
    process.stdout.write(text + '\n');
    child.stdin.write(text + '\n');
  }

  child.stdout.on('data', onData(process.stdout));
  child.stderr.on('data', onData(process.stderr));
  process.stdin.pipe(child.stdin, { end: false }); // you can still type answers in the terminal
}

child.on('exit', async code => {
  await post('/task', { phase: 'end', id, ok: code === 0, exitCode: code ?? 1 }, 800);
  process.exit(code ?? 1);
});
