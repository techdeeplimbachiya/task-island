#!/usr/bin/env node
// Claude Code hook -> Task Island. Forwards status events; for PermissionRequest it
// waits for your Allow/Deny click. If the island isn't running (or you don't answer
// in time) it prints nothing and Claude shows its normal terminal prompt.
const http = require('http');
const path = require('path');

const PORT = 47823;
const ASK_WAIT_MS = 110_000; // keep below "timeout" (120 s) in settings.json

let raw = '';
process.stdin.on('data', c => (raw += c));
process.stdin.on('end', main);

function post(route, data, timeoutMs) {
  return new Promise(resolve => {
    const body = JSON.stringify(data);
    const req = http.request({
      host: '127.0.0.1', port: PORT, path: route, method: 'POST', timeout: timeoutMs,
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
    }, res => { let out = ''; res.on('data', c => (out += c)); res.on('end', () => resolve(out)); });
    req.on('error', () => resolve(null));
    req.on('timeout', () => { req.destroy(); resolve(null); });
    req.end(body);
  });
}

function summarize(tool, input = {}) {
  switch (tool) {
    case 'Bash': case 'PowerShell': return input.command;
    case 'Read': case 'Write': case 'Edit': case 'MultiEdit': return path.basename(input.file_path || '');
    case 'Grep': case 'Glob': return input.path ? `${input.pattern}  in  ${input.path}` : input.pattern;
    case 'WebFetch': return input.url;
    case 'WebSearch': return input.query;
    case 'Task': return input.description;
    default: return '';
  }
}

async function main() {
  let ev;
  try { ev = JSON.parse(raw); } catch { process.exit(0); }
  const project = path.basename(ev.cwd || '');
  const detail = String(summarize(ev.tool_name, ev.tool_input) || '').slice(0, 200);

  if (ev.hook_event_name === 'PermissionRequest') {
    // "Always allow" = the rules Claude Code would add for its "Yes, and don't ask again" option.
    // setMode entries are skipped so the island never silently switches your permission mode.
    const always = (ev.permission_suggestions || []).filter(s => s && s.type !== 'setMode');
    const out = await post('/ask', {
      source: 'claude', session: ev.session_id, project,
      title: `Allow ${ev.tool_name || 'action'}?`, detail: detail || ev.tool_name,
      yes: 'Allow once', no: 'Deny', always: always.length ? 'Always allow' : '',
    }, ASK_WAIT_MS);
    let answer;
    try { answer = JSON.parse(out).answer; } catch {}
    // "dismiss" (or no answer) prints nothing, so the terminal prompt stays in charge
    const decision =
      answer === 'yes'    ? { behavior: 'allow' } :
      answer === 'always' ? { behavior: 'allow', updatedPermissions: always } :
      answer === 'no'     ? { behavior: 'deny', message: 'Denied from Task Island' } : null;
    if (decision) {
      process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: 'PermissionRequest', decision } }));
    }
    process.exit(0);
  }

  await post('/event', {
    session: ev.session_id, project, event: ev.hook_event_name,
    tool: ev.tool_name, detail, message: ev.message,
  }, 1500);
  process.exit(0);
}
