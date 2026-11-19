#!/usr/bin/env node
// Daily token statistics: once a day, writes the token usage of all Claude Code sessions
// (subagents included) into a CSV file, one row per day x model x effort, with the cost at
// Claude API list prices of the model that was really used.
//
// Source: the session transcripts in ~/.claude/projects/**/*.jsonl. Claude Code deletes them
// after about 30 days, so this script keeps the numbers in the CSV for good.
//
// Usage:
//   hook     Stop hook: runs at most once a day and starts "run" in the background (about 0.5 s)
//   run      append all finished days (up to yesterday) that are missing in the CSV
//   cron     like "run", in the foreground (daily schedule, see cron.sh)
//   rebuild  write the CSV again from all transcripts that still exist (old file -> *.bak_<time>)
//   status   last run and the last log lines
//
// See README.md in this folder.

'use strict';
const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { spawn } = require('child_process');

// ======================= SETTINGS (take effect on the next run) =======================
// Folder for the CSV files, the log and the state file. Must be readable by Home Assistant
// if you use the sensor (ha_package.yaml): /share is visible in the add-on and in Core.
const DATA_DIR = process.env.CLAUDE_USAGE_DIR || '/share/claude_usage';
const CSV_FILE = path.join(DATA_DIR, 'claude_token_usage.csv');
const TRANSCRIPT_DIR = path.join(process.env.HOME || '/root', '.claude', 'projects');
const TIME_ZONE = process.env.TZ || Intl.DateTimeFormat().resolvedOptions().timeZone; // day boundary
const CSV_DELIMITER = ',';      // ';' for spreadsheet programs with a decimal comma
const DECIMAL_COMMA = false;    // true: 1,2345 instead of 1.2345
// Claude API list prices, USD per million tokens (input, cache write 1 h, cache write 5 min,
// cache read, output), as of November 2026. Key = start of the model ID, the longest match wins.
// A model that is missing here gets an empty cost and is named in the log: add it.
const PRICES = {
  'claude-fable-5-2':  [8, 16, 10, 0.20, 40],
  'claude-fable-5-1':  [10, 20, 12.5, 0.25, 50],
  'claude-fable-5':    [10, 20, 12.5, 1.00, 50],
  'claude-opus-5-5':   [4, 8, 5, 0.20, 20],
  'claude-opus-5':     [5, 10, 6.25, 0.50, 25],
  'claude-opus-4':     [5, 10, 6.25, 0.50, 25],
  'claude-sonnet-5-5': [2, 4, 2.5, 0.10, 10],
  'claude-sonnet-5':   [2, 4, 2.5, 0.20, 10],
  'claude-sonnet-4':   [3, 6, 3.75, 0.30, 15],
  'claude-haiku-5-5':  [0.10, 0.20, 0.125, 0.01, 0.50],
  'claude-haiku-4':    [1, 2, 1.25, 0.10, 5],
};
// ========================================================================================

const STATE_FILE = path.join(DATA_DIR, '.token_daily_stats.json');
const LOG_FILE = path.join(DATA_DIR, 'token_daily_stats.log');
const LOCK_FILE = path.join(DATA_DIR, '.token_daily_stats.lock');
const COLUMNS = ['date', 'model', 'effort', 'requests', 'input', 'cache_write_1h', 'cache_write_5m',
  'cache_read', 'output', 'thinking', 'cost_usd'];

const dayFmt = new Intl.DateTimeFormat('sv-SE', { timeZone: TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit' });
const localDay = (d) => dayFmt.format(d); // "YYYY-MM-DD"

function log(text) {
  const time = new Date().toLocaleString('sv-SE', { timeZone: TIME_ZONE });
  try { fs.appendFileSync(LOG_FILE, `${time} ${text}\n`); } catch (_) { /* ignore */ }
}
function readState() { try { return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8')); } catch (_) { return {}; } }
function writeState(s) { fs.writeFileSync(STATE_FILE, JSON.stringify(s, null, 2)); }

function priceFor(model) {
  const key = Object.keys(PRICES).filter((k) => model.startsWith(k)).sort((a, b) => b.length - a.length)[0];
  return key ? PRICES[key] : null;
}

function allJsonl(dir) {
  const out = [];
  const walk = (d) => {
    let entries;
    try { entries = fs.readdirSync(d, { withFileTypes: true }); } catch (_) { return; }
    for (const e of entries) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith('.jsonl')) out.push(p);
    }
  };
  walk(dir);
  return out;
}

// Reads every API request once (message id + request id; the same answer is often logged several times).
async function readRequests() {
  const requests = new Map();
  for (const file of allJsonl(TRANSCRIPT_DIR)) {
    const rl = readline.createInterface({ input: fs.createReadStream(file), crlfDelay: Infinity });
    for await (const line of rl) {
      if (!line.includes('"usage"') || !line.includes('"assistant"')) continue;
      let d;
      try { d = JSON.parse(line); } catch (_) { continue; }
      if (d.type !== 'assistant' || !d.message || !d.message.usage) continue;
      const m = d.message;
      if (!m.model || m.model === '<synthetic>') continue;
      const time = new Date(d.timestamp);
      if (Number.isNaN(time.getTime())) continue;
      const u = m.usage;
      const cc = u.cache_creation || {};
      const r = {
        time, model: m.model, effort: d.effort || 'unknown',
        input: u.input_tokens || 0,
        cache_1h: cc.ephemeral_1h_input_tokens || 0,
        cache_5m: cc.ephemeral_5m_input_tokens || 0,
        cache_read: u.cache_read_input_tokens || 0,
        output: u.output_tokens || 0,
        thinking: (u.output_tokens_details && u.output_tokens_details.thinking_tokens) || 0,
      };
      // No split given: count cache writes as 1 h (Claude Code uses the 1-hour TTL)
      const written = u.cache_creation_input_tokens || 0;
      if (r.cache_1h + r.cache_5m !== written) r.cache_1h = Math.max(written - r.cache_5m, 0);
      const key = `${m.id}|${d.requestId}`;
      const old = requests.get(key);
      if (!old || r.output > old.output) requests.set(key, r);
    }
  }
  return [...requests.values()];
}

const num = (x, digits) => { const s = x.toFixed(digits); return DECIMAL_COMMA ? s.replace('.', ',') : s; };

function rowsFor(requests, days, unknown) {
  const g = new Map();
  for (const r of requests) {
    const day = localDay(r.time);
    if (!days.has(day)) continue;
    const key = [day, r.model, r.effort].join('|');
    let s = g.get(key);
    if (!s) {
      s = { day, model: r.model, effort: r.effort, n: 0, input: 0, cache_1h: 0, cache_5m: 0, cache_read: 0, output: 0, thinking: 0 };
      g.set(key, s);
    }
    s.n++;
    for (const k of ['input', 'cache_1h', 'cache_5m', 'cache_read', 'output', 'thinking']) s[k] += r[k];
  }
  const rows = [...g.values()].sort((x, y) => x.day.localeCompare(y.day) || x.model.localeCompare(y.model) || x.effort.localeCompare(y.effort));
  return rows.map((s) => {
    const p = priceFor(s.model);
    if (!p) unknown.add(s.model);
    const cost = p ? (s.input * p[0] + s.cache_1h * p[1] + s.cache_5m * p[2] + s.cache_read * p[3] + s.output * p[4]) / 1e6 : null;
    return [s.day, s.model, s.effort, s.n, s.input, s.cache_1h, s.cache_5m, s.cache_read, s.output, s.thinking,
      cost === null ? '' : num(cost, 4)].join(CSV_DELIMITER);
  });
}

function lastDayInCsv() {
  let text;
  try { text = fs.readFileSync(CSV_FILE, 'utf8'); } catch (_) { return null; }
  let max = null;
  for (const line of text.split('\n').slice(1)) {
    const t = line.slice(0, 10);
    if (/^\d{4}-\d{2}-\d{2}$/.test(t) && (!max || t > max)) max = t;
  }
  return max;
}

async function run(rebuild) {
  let fd;
  try { fd = fs.openSync(LOCK_FILE, 'wx'); } catch (_) {
    // A lock older than 30 minutes is left over from a run that was killed
    try { if (Date.now() - fs.statSync(LOCK_FILE).mtimeMs < 30 * 60e3) { log('skipped: already running'); return; } } catch (_) { /* gone */ }
    fs.rmSync(LOCK_FILE, { force: true });
    fd = fs.openSync(LOCK_FILE, 'wx');
  }
  fs.writeSync(fd, String(process.pid)); fs.closeSync(fd);
  try {
    const t0 = Date.now();
    if (rebuild && fs.existsSync(CSV_FILE)) {
      const stamp = new Date().toISOString().replace(/[-:]/g, '').replace('T', '_').slice(0, 15);
      fs.renameSync(CSV_FILE, `${CSV_FILE}.bak_${stamp}`);
    }
    const today = localDay(new Date());
    const last = lastDayInCsv();
    const requests = await readRequests();
    const days = new Set();
    for (const r of requests) { const t = localDay(r.time); if (t < today && (!last || t > last)) days.add(t); }
    const unknown = new Set();
    const rows = rowsFor(requests, days, unknown);
    if (!fs.existsSync(CSV_FILE)) fs.writeFileSync(CSV_FILE, COLUMNS.join(CSV_DELIMITER) + '\n');
    if (rows.length) fs.appendFileSync(CSV_FILE, rows.join('\n') + '\n');
    log(`${rows.length} rows for ${days.size} day(s) [${[...days].sort().join(', ') || '-'}] in ${((Date.now() - t0) / 1000).toFixed(1)} s; `
      + `${requests.length} requests read` + (unknown.size ? `; NO PRICE for: ${[...unknown].join(', ')} (add to PRICES)` : ''));
    const st = readState(); st.last_run = today; st.last_success = new Date().toISOString(); writeState(st);
  } finally {
    fs.rmSync(LOCK_FILE, { force: true });
  }
}

async function main() {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  const mode = process.argv[2] || 'status';
  if (mode === 'hook') {
    // Stop hook: ignore stdin, print nothing, start the work in the background at most once a day
    const today = localDay(new Date());
    const st = readState();
    if (st.last_attempt === today) return;
    st.last_attempt = today; writeState(st);
    spawn(process.execPath, [__filename, 'run'], { detached: true, stdio: 'ignore' }).unref();
  } else if (mode === 'cron') {
    const st = readState(); st.last_attempt = localDay(new Date()); writeState(st);
    try { await run(false); } catch (e) { log(`ERROR: ${e && e.stack || e}`); process.exitCode = 1; }
  } else if (mode === 'run' || mode === 'rebuild') {
    try { await run(mode === 'rebuild'); } catch (e) { log(`ERROR: ${e && e.stack || e}`); process.exitCode = 1; }
  } else if (mode === 'status') {
    console.log(JSON.stringify(readState(), null, 2));
    try { console.log(fs.readFileSync(LOG_FILE, 'utf8').trim().split('\n').slice(-5).join('\n')); } catch (_) { console.log('(no log yet)'); }
  } else {
    console.error('Usage: token_daily_stats.js hook|cron|run|rebuild|status');
    process.exitCode = 2;
  }
}
main();
