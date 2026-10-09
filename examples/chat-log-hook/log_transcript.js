#!/usr/bin/env node
// Claude Code Stop hook: appends the new prompts and answers of the session to
// a daily Markdown file, so a conversation can be read again after it has
// scrolled out of the terminal. See README.md next to this file.
//
// Claude Code runs it after every answer and passes session_id and
// transcript_path on stdin. The transcript is a JSONL file; the line count
// already written is kept per session, so nothing is written twice.

const fs = require('fs');
const path = require('path');

// Where the log goes. /homeassistant survives add-on restarts and updates.
const LOG_DIR = process.env.CHAT_LOG_DIR || '/homeassistant/claude_chat_log';
const STATE_DIR = path.join(LOG_DIR, '.state');

function localDateStr(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function localTimeStr(d) {
  return d.toTimeString().slice(0, 8);
}

let input = '';
process.stdin.on('data', (d) => (input += d));
process.stdin.on('end', () => {
  try {
    const hookInput = JSON.parse(input || '{}');
    const transcriptPath = hookInput.transcript_path;
    const sessionId = hookInput.session_id || 'unknown';

    if (!transcriptPath || !fs.existsSync(transcriptPath)) {
      process.exit(0);
    }

    fs.mkdirSync(STATE_DIR, { recursive: true });
    const stateFile = path.join(STATE_DIR, `${sessionId}.offset`);

    let lastLine = 0;
    if (fs.existsSync(stateFile)) {
      lastLine = parseInt(fs.readFileSync(stateFile, 'utf8').trim(), 10) || 0;
    }

    const allLines = fs.readFileSync(transcriptPath, 'utf8').split('\n').filter(Boolean);
    if (allLines.length <= lastLine) {
      process.exit(0);
    }

    // Two sessions (for example a second tmux window) write into the same
    // file, so every heading carries the start of the session ID.
    const session = sessionId.slice(0, 8);
    const entries = [];

    for (const line of allLines.slice(lastLine)) {
      let d;
      try {
        d = JSON.parse(line);
      } catch (e) {
        continue;
      }
      if (d.type !== 'user' && d.type !== 'assistant') continue;
      // Subagent conversations
      if (d.isSidechain) continue;

      const msg = d.message;
      if (!msg || !msg.content) continue;

      // Text only: tool calls and tool results are left out
      let text = '';
      if (typeof msg.content === 'string') {
        text = msg.content;
      } else if (Array.isArray(msg.content)) {
        text = msg.content
          .filter((b) => b.type === 'text')
          .map((b) => b.text)
          .join('\n');
      }
      text = text.trim();
      if (!text) continue;

      const ts = d.timestamp ? new Date(d.timestamp) : new Date();
      // The summary after /compact or auto-compact is stored as a user
      // message (isCompactSummary), so label it as what it is
      const speaker = d.isCompactSummary ? 'SUMMARY (/compact)' : d.type === 'user' ? 'USER' : 'CLAUDE';
      entries.push(`### ${speaker} — ${localTimeStr(ts)} · session ${session}\n\n${text}\n`);
    }

    if (entries.length > 0) {
      const dateStr = localDateStr(new Date());
      const outFile = path.join(LOG_DIR, `${dateStr}.md`);
      let chunk = '';
      if (!fs.existsSync(outFile)) {
        chunk += `# Claude Code chat log ${dateStr}\n\n`;
      }
      chunk += entries.join('\n---\n\n') + '\n';
      fs.appendFileSync(outFile, chunk);
    }

    fs.writeFileSync(stateFile, String(allLines.length));
    process.exit(0);
  } catch (e) {
    // A hook must never block the session
    process.exit(0);
  }
});
