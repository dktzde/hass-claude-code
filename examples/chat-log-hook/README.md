# Chat log hook

A [Claude Code hook](https://docs.anthropic.com/en/docs/claude-code/hooks) that writes your conversations with Claude into one Markdown file per day, with a separate file for each Claude session running in parallel. Use it to read an answer again after it has scrolled out of the terminal, or to look up what Claude did a few days ago.

## What it does

Claude Code runs a **Stop hook** every time Claude finishes an answer. This hook, [`log_transcript.js`](log_transcript.js), then:

1. Reads the transcript of the session. Claude Code passes its path on stdin.
2. Takes only the lines added since its last run. It keeps the line count per session in `.state/<session ID>.offset`, so nothing is written twice.
3. Appends your prompts and Claude's text answers to a file in `/homeassistant/claude_chat_log/`, one new file per day (local date) and per tmux window:

   | tmux window | Session | File |
   |---|---|---|
   | 0 | Claude in the sidebar panel | `YYYY-MM-DD.md` |
   | 1 | second session (see [Quick guide](../../README.md#quick-guide)) | `YYYY-MM-DD_claude2.md` |
   | 2 | third session | `YYYY-MM-DD_claude3.md` |

   It asks tmux for the window through `TMUX_PANE`, which the hook inherits from Claude Code. Without tmux, or if the lookup fails, it writes `YYYY-MM-DD.md`.

Each entry gets a heading with the speaker, the time and the start of the session ID:

```markdown
### USER — 08:15:02 · session 76fb0c12

Which lights are on?

---

### CLAUDE — 08:15:09 · session 76fb0c12

Two lights are on: ...
```

- Tool calls, tool output and subagent conversations are left out. Only the text you read in the terminal ends up in the file.
- After `/compact` or an automatic compaction, the summary Claude continues with shows up as `SUMMARY (/compact)`.
- The file belongs to the window, not to the conversation: after `/clear` or a restart of Claude in the same window, the log goes on in the same file. The session ID in the heading shows where a new conversation starts.
- The hook never blocks Claude: on any error it exits silently.

## Install

You can ask Claude to do it for you: "Install the chat log hook from github.com/dktzde/hass-claude-code/tree/main/examples/chat-log-hook". Or by hand in the add-on terminal:

1. Copy the script into your configuration folder, which survives add-on restarts and updates:

   ```bash
   mkdir -p /homeassistant/.claude/hooks
   curl -fsSL -o /homeassistant/.claude/hooks/log_transcript.js \
     https://raw.githubusercontent.com/dktzde/hass-claude-code/main/examples/chat-log-hook/log_transcript.js
   ```

2. Register the hook in `/homeassistant/.claude/settings.local.json`. If the file already exists, add the `hooks` part to it instead of replacing the file:

   ```json
   {
     "hooks": {
       "Stop": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "node /homeassistant/.claude/hooks/log_transcript.js",
               "timeout": 15
             }
           ]
         }
       ]
     }
   }
   ```

3. Type `/hooks` in Claude Code and check that the Stop hook is listed. If it is not, restart Claude Code.

After the next answer, the first file of the day appears in `/homeassistant/claude_chat_log/`. Open it with the File editor or Studio Code Server add-on, or through the `config` Samba share.

## Settings and notes

- **Other folder:** set `CHAT_LOG_DIR` in the command, for example `"command": "CHAT_LOG_DIR=/share/claude_chat_log node /homeassistant/.claude/hooks/log_transcript.js"`. Use a folder that survives restarts: `/homeassistant`, `/share` or `/config`.
- **Privacy:** the log holds everything you and Claude write, including anything secret you paste into the chat. It is part of your Home Assistant backups. If you keep your configuration in a git repository, add `claude_chat_log/` to `.gitignore`.
- **Size:** the files are never cleaned up. Delete old days by hand when you no longer need them.
