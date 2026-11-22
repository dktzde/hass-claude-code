# Usage tracker

Scripts that keep track of how much you use Claude Code in this add-on:

- **Daily token statistics:** once a day, the tokens of all sessions go into a CSV file, one row per day, model and effort, with the cost at Claude API list prices. You can see what your subscription would cost as pay-as-you-go API use.
- **Weekly limit:** every few hours, the numbers of `/usage` (percent of the weekly limit, session, share of Claude Code) go into a second CSV file, with a projection to the end of the weekly window.
- **Home Assistant sensor (optional):** `sensor.claude_usage` with the costs and the latest weekly limit, plus an example dashboard card.

Nothing here is part of the add-on image. You copy the files and set up two hooks yourself.

## Files

| File | What it does |
|---|---|
| [`token_daily_stats.js`](token_daily_stats.js) | Reads the session transcripts in `~/.claude/projects/` and appends all finished days to `claude_token_usage.csv`. Started by a Stop hook (at most once a day, in the background) and by the daily schedule. |
| [`weekly_limit.py`](weekly_limit.py) | Reads the weekly limit and appends a row to `weekly_limit.csv`. `read` writes a row and prints a short summary, `api` only shows the answer of the endpoint. |
| [`cron.sh`](cron.sh) | Sets up the schedule in the add-on (busybox `crond`) and runs both scripts. |
| [`costs_sensor.py`](costs_sensor.py), [`ha_package.yaml`](ha_package.yaml) | `command_line` sensor for Home Assistant. |
| [`example_card.yaml`](example_card.yaml) | Markdown card for a dashboard. |

Each script has a **SETTINGS** block at the top: folders, schedule, CSV format, prices.

## Install

1. Copy this folder to `/homeassistant/claude_usage/` (Home Assistant Core sees it as `/config/claude_usage/`). If you pick another folder, change `DIR` in `cron.sh` and the path in `ha_package.yaml`.
2. Add two hooks to `/homeassistant/.claude/settings.json` (create the file if it does not exist; merge with hooks you already have):

   ```json
   {
     "hooks": {
       "SessionStart": [{ "hooks": [{ "type": "command", "command": "sh /homeassistant/claude_usage/cron.sh ensure", "timeout": 10 }] }],
       "Stop": [{ "hooks": [{ "type": "command", "command": "node /homeassistant/claude_usage/token_daily_stats.js hook", "timeout": 10 }] }]
     }
   }
   ```

   The SessionStart hook adds the schedule and starts `crond`. The Stop hook is a fallback in case the schedule did not run.
3. Fill the daily CSV once by hand. It goes back as far as Claude Code still keeps transcripts (about 30 days) and takes about half a minute:

   ```sh
   node /homeassistant/claude_usage/token_daily_stats.js run
   python3 /homeassistant/claude_usage/weekly_limit.py read
   ```

4. Optional: copy `ha_package.yaml` to `/config/packages/claude_usage.yaml` and restart Home Assistant once. Then add the card from `example_card.yaml`.

The CSV files and logs are in `/share/claude_usage/`. You can open them in a spreadsheet through the Samba share `share`. If your spreadsheet program uses a decimal comma, set `CSV_DELIMITER = ';'` and `DECIMAL_COMMA` to true in both scripts and in `costs_sensor.py` before the first run.

## Columns

`claude_token_usage.csv`: `date`, `model`, `effort`, `requests`, `input`, `cache_write_1h`, `cache_write_5m`, `cache_read`, `output`, `thinking` (part of `output`), `cost_usd`.

`weekly_limit.csv`: `date`, `time`, `source` (label of the run), `window_start`, `window_end`, `week_passed_pct`, `limit_used_pct`, `session_pct`, `claude_code_share_pct`, `claude_code_points`, `other_points` (percentage points of the limit), `projection_linear_pct`, `projection_pattern_pct`, `cost_window_usd` (cost of the window so far, from the daily CSV), `raw` (what was read, for checking).

## How the projection works

Projection = percent used ÷ the share of the week that has passed.

- **linear:** hours passed ÷ 168.
- **pattern:** the share of the week that has passed according to your typical weekday pattern. The pattern is the mean cost per weekday from the daily CSV. It needs at least 14 days; the current day counts by the time of day.

Below 2 % of the week (the first hours after the reset) there is no projection.

## Limits

- **The usage endpoint is not documented.** `weekly_limit.py` uses the same endpoint as `/usage` in Claude Code (`api.anthropic.com/api/oauth/usage`). It can change at any time. Then the `raw` column shows `API ERROR: …` and the script falls back to reading `/usage` in a separate tmux session. That fallback has no Claude Code share and depends on the screen layout of `/usage`.
- **Your login token:** the script reads the OAuth token from `~/.claude/.credentials.json` on each run and sends it only to `api.anthropic.com`. It never prints, stores or refreshes it. When the token has expired (no session open for a while), the tmux fallback starts Claude Code, which refreshes it.
- **Costs are an estimate.** They use the list prices in `PRICES` (November 2026) and the token counts in the transcripts. They are not a bill. A model missing in `PRICES` gets no cost and is named in `token_daily_stats.log`.
- **Transcripts disappear after about 30 days.** Days that were not written by then are lost. `rebuild` writes the CSV again, but only from the transcripts that still exist (the old file is kept as `*.bak_<time>`).
- **The schedule only runs while the add-on runs.** After an add-on restart, open Claude Code once so the SessionStart hook sets it up again.

## Credits

The request to the usage endpoint (URL, headers and fields) follows [`claude-usage-mcp`](https://github.com/anatoly-lab/claude-usage-mcp) by Anatoly Tarnavsky (MIT). No code was copied.
