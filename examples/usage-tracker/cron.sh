#!/bin/sh
# Schedule for the usage tracker inside the add-on (busybox crond).
# /etc/crontabs and crond do not survive an add-on restart, so a SessionStart hook calls "ensure":
# it adds the lines that are missing and starts crond. Open Claude Code once after a restart.
#
# Usage:  ensure          add the schedule lines + start crond (SessionStart hook, prints nothing)
#         daily           daily token statistics + refresh the Home Assistant sensor
#         weekly <label>  read the weekly limit (weekly_limit.py), notify Home Assistant on failure
#
# See README.md in this folder.

# ══ SETTINGS (take effect on the next "ensure"; after changing a time, delete the old line in /etc/crontabs/root) ══
DIR=/homeassistant/claude_usage                 # folder of these scripts (/config/claude_usage in Home Assistant Core)
DAILY_TIME="10 0 * * *"                         # 00:10 local time: daily token statistics for yesterday
WEEKLY_TIME="0 */4 * * *"                       # every 4 hours: weekly limit (one HTTP request, no model call)
SENSOR="sensor.claude_usage"                    # refreshed after the daily run (empty = none)
NOTIFY=true                                     # persistent notification in Home Assistant if the weekly limit cannot be read
# ════════════════════════════════════════════════════════════════════════════════════════════════

TAB=/etc/crontabs/root
TOKEN_FILE=/run/s6/container_environment/SUPERVISOR_TOKEN   # read at run time only, never written anywhere
LOG="${CLAUDE_USAGE_DIR:-/share/claude_usage}/cron.log"

# crond has almost no environment: set what Claude Code and the scripts need
export HOME=/root TERM=xterm-256color PATH="/root/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
export TZ="${TZ:-$(cat /run/s6/container_environment/TZ 2>/dev/null)}"

ha_post() {  # ha_post <path> <json>
  curl -s -o /dev/null -w "%{http_code}" -X POST -H "Authorization: Bearer $(cat "$TOKEN_FILE")" \
    -H "Content-Type: application/json" -d "$2" "http://supervisor/core/api/$1"
}

case "$1" in
  ensure)
    before=$(cksum < "$TAB" 2>/dev/null)
    grep -qF "$DIR/cron.sh daily" "$TAB" 2>/dev/null || echo "$DAILY_TIME sh $DIR/cron.sh daily" >> "$TAB"
    grep -qF "$DIR/cron.sh weekly" "$TAB" 2>/dev/null || echo "$WEEKLY_TIME sh $DIR/cron.sh weekly schedule" >> "$TAB"
    # a running busybox crond reads changed lines only when told so
    [ "$(cksum < "$TAB")" = "$before" ] || echo root >> /etc/crontabs/cron.update
    pgrep -x crond >/dev/null || crond -b
    ;;
  daily)
    mkdir -p "$(dirname "$LOG")"
    node "$DIR/token_daily_stats.js" cron
    if [ -n "$SENSOR" ]; then
      code=$(ha_post services/homeassistant/update_entity "{\"entity_id\": \"$SENSOR\"}")
      echo "$(date '+%Y-%m-%d %H:%M:%S') daily: $SENSOR refreshed (HTTP $code)" >> "$LOG"
    fi
    ;;
  weekly)
    mkdir -p "$(dirname "$LOG")"
    python3 "$DIR/weekly_limit.py" read "${2:-schedule}" >> "$LOG" 2>&1
    rc=$?
    echo "$(date '+%Y-%m-%d %H:%M:%S') weekly: finished (exit $rc)" >> "$LOG"
    if [ "$rc" != 0 ] && [ "$NOTIFY" = true ]; then
      ha_post services/persistent_notification/create \
        '{"notification_id": "claude_weekly_limit", "title": "Claude weekly limit", "message": "The weekly limit could be read neither from the usage endpoint nor from /usage. See the column raw in weekly_limit.csv."}' >/dev/null
    fi
    ;;
  *)
    echo "Usage: cron.sh ensure|daily|weekly [label]" >&2; exit 2 ;;
esac
exit 0
