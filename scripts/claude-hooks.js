#!/usr/bin/env node
// Adds (or removes) the Task Island hooks in ~/.claude/settings.json without touching
// anything else in the file. Safe to run more than once.
//   node scripts/claude-hooks.js install
//   node scripts/claude-hooks.js uninstall
const fs = require('fs');
const os = require('os');
const path = require('path');

const mode = process.argv[2] === 'uninstall' ? 'uninstall' : 'install';
const file = path.join(os.homedir(), '.claude', 'settings.json');
const hookPath = path.resolve(__dirname, '..', 'integrations', 'claude', 'island-hook.js').replace(/\\/g, '/');
const command = `node "${hookPath}"`;
const EVENTS = { UserPromptSubmit: null, PreToolUse: '*', PostToolUse: '*', Notification: null, Stop: null, PermissionRequest: '*' };

let settings = {};
if (fs.existsSync(file)) {
  const raw = fs.readFileSync(file, 'utf8').replace(/^﻿/, '');
  if (raw.trim()) {
    try { settings = JSON.parse(raw); }
    catch (e) {
      console.error(`X ${file} is not valid JSON (${e.message}).\n  Fix that file first. Nothing was changed.`);
      process.exit(1);
    }
  }
  fs.copyFileSync(file, `${file}.task-island.bak`);
}

settings.hooks = settings.hooks || {};
for (const [event, matcher] of Object.entries(EVENTS)) {
  // drop any earlier Task Island hook (old path or duplicate), keep everyone else's hooks
  const groups = (settings.hooks[event] || [])
    .map(g => ({ ...g, hooks: (g.hooks || []).filter(h => !String(h.command || '').includes('island-hook.js')) }))
    .filter(g => g.hooks.length);
  if (mode === 'install') {
    const hook = { type: 'command', command };
    if (event === 'PermissionRequest') hook.timeout = 120;
    groups.push(matcher ? { matcher, hooks: [hook] } : { hooks: [hook] });
  }
  if (groups.length) settings.hooks[event] = groups; else delete settings.hooks[event];
}
if (!Object.keys(settings.hooks).length) delete settings.hooks;

fs.mkdirSync(path.dirname(file), { recursive: true });
fs.writeFileSync(file, JSON.stringify(settings, null, 2) + '\n');
console.log(`OK Claude Code hooks ${mode === 'install' ? 'added to' : 'removed from'} ${file}`);
