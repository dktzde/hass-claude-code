#!/usr/bin/env python3
"""Weekly limit of a Claude subscription (the numbers of /usage) with a projection to the end of the window.

Writes one row per run to weekly_limit.csv: percent of the weekly limit used, session percent, the share of
Claude Code, how much of the week has passed, and a projection to the reset (linear and by weekday pattern).

Usage (inside the add-on, as root):
  python3 weekly_limit.py read [label]   read the numbers, append a row (label = free text for the "source" column,
                                          default "manual"), print a short summary; exit code 1 = nothing readable
  python3 weekly_limit.py api            only query the usage endpoint and print the answer, writes nothing (test)
  python3 weekly_limit.py status         last rows

How the numbers are read:
  1. The usage endpoint that /usage in Claude Code uses (undocumented, see README.md). It also returns the share of
     Claude Code. The OAuth token is read from the Claude Code login file on every run, never printed or stored.
  2. If that fails (endpoint changed, token expired): start `claude` in a separate tmux session, type /usage and read
     the screen (about 30 s, no model call, never touches your own session). Starting Claude also refreshes an expired
     token, so the endpoint is tried a second time afterwards. The screen has no Claude Code share.

Projection = percent used / share of the week that has passed:
  linear  = hours passed / 168
  pattern = typical share per weekday from the daily token CSV (token_daily_stats.js, column cost_usd); needs
            PATTERN_MIN_DAYS days, the current day counts by the time of day.
"""
import csv
import datetime as dt
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

# ══ SETTINGS ═══════════════════════════════════════════════════════════════════════════════════
DATA_DIR = Path(os.environ.get("CLAUDE_USAGE_DIR", "/share/claude_usage"))  # same folder as token_daily_stats.js
CSV_FILE = DATA_DIR / "weekly_limit.csv"
DAILY_CSV = DATA_DIR / "claude_token_usage.csv"  # from token_daily_stats.js (for the weekday pattern)
LOG_FILE = DATA_DIR / "weekly_limit.log"
CSV_DELIMITER = ","  # ";" for spreadsheet programs with a decimal comma
DECIMAL_COMMA = False  # True: 12,5 instead of 12.5
WINDOW_DAYS = 7
PATTERN_MIN_DAYS = 14  # fewer days in the daily CSV -> no pattern projection
MIN_SHARE = 0.02  # less of the week passed (first ~3 h) -> no projection
USAGE_URL = "https://api.anthropic.com/api/oauth/usage"  # the endpoint behind /usage (undocumented)
USAGE_BETA = "oauth-2025-04-20"  # header anthropic-beta
CREDENTIALS = Path(os.environ.get("HOME", "/root")) / ".claude" / ".credentials.json"  # Claude Code login (read only)
USER_AGENT_FALLBACK = "claude-code/2.1.0"  # used if `claude --version` fails (without a real-looking agent: HTTP 429)
API_TIMEOUT_S = 20
TMUX_NAME = f"usagecap_{os.getpid()}"  # separate tmux session per run, only for the fallback
WORK_DIR = "/homeassistant"  # must be a trusted folder, or Claude asks first
WAIT_START_S = 60  # wait this long for the Claude prompt
WAIT_USAGE_S = 40  # wait this long for the numbers in /usage
# ═══════════════════════════════════════════════════════════════════════════════════════════════

COLUMNS = ["date", "time", "source", "window_start", "window_end", "week_passed_pct", "limit_used_pct",
           "session_pct", "claude_code_share_pct", "claude_code_points", "other_points",
           "projection_linear_pct", "projection_pattern_pct", "cost_window_usd", "raw"]
FMT = "%Y-%m-%d %H:%M"
MONTHS = {m: i + 1 for i, m in enumerate("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split())}


def log(text):
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"{dt.datetime.now():%Y-%m-%d %H:%M:%S} {text}\n")
    except OSError:
        pass


def fmt(x, digits=1):
    if x is None:
        return ""
    s = f"{x:.{digits}f}"
    return s.replace(".", ",") if DECIMAL_COMMA else s


def number(s):
    return float((s or "0").replace(",", "."))


# ── CSV ─────────────────────────────────────────────────────────────────────────────────────
def read_rows():
    if not CSV_FILE.exists():
        return []
    with open(CSV_FILE, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f, delimiter=CSV_DELIMITER))


def write_row(r):
    new = not CSV_FILE.exists() or CSV_FILE.stat().st_size == 0
    with open(CSV_FILE, "a", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter=CSV_DELIMITER)
        if new:
            w.writerow(COLUMNS)
        w.writerow([r.get(c, "") for c in COLUMNS])


# ── Window and projection ───────────────────────────────────────────────────────────────────
def window_end(now, rows):
    """End of the window 'now' lies in, from the latest known reset (shifted by whole weeks); None if unknown."""
    for r in reversed(rows):
        try:
            end = dt.datetime.strptime(r.get("window_end", ""), FMT)
        except ValueError:
            continue
        week = dt.timedelta(days=WINDOW_DAYS)
        while end <= now:
            end += week
        while end - week > now:
            end -= week
        return end
    return None


def daily_costs():
    """{date: cost} from the daily CSV, gaps between first and last day = 0. Empty if there is none."""
    if not DAILY_CSV.exists():
        return {}
    total = {}
    with open(DAILY_CSV, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f, delimiter=CSV_DELIMITER):
            try:
                d = dt.date.fromisoformat(r["date"])
                total[d] = total.get(d, 0.0) + number(r.get("cost_usd"))
            except (KeyError, ValueError):
                continue
    if total:
        d, last = min(total), max(total)
        while d <= last:
            total.setdefault(d, 0.0)
            d += dt.timedelta(days=1)
    return total


def pattern_share(start, end, now, costs):
    """Share of the weekly use that has passed by 'now' according to the typical weekday pattern (0..1) or None."""
    if len(costs) < PATTERN_MIN_DAYS:
        return None
    if now >= end:
        return 1.0
    per_day = {w: [] for w in range(7)}
    for d, k in costs.items():
        per_day[d.weekday()].append(k)
    mean = {w: (sum(v) / len(v) if v else 0.0) for w, v in per_day.items()}

    def overlap(day, a, b):  # part of the calendar day that lies between a and b (0..1)
        d0 = dt.datetime.combine(day, dt.time())
        lo, hi = max(d0, a), min(d0 + dt.timedelta(days=1), b)
        return max((hi - lo).total_seconds(), 0.0) / 86400

    total = passed = 0.0
    day = start.date()
    while day <= end.date():  # every calendar day the window touches, the partial first and last ones included
        m = mean[day.weekday()]
        total += m * overlap(day, start, end)
        passed += m * overlap(day, start, now)
        day += dt.timedelta(days=1)
    return passed / total if total > 0 else None


def calc(now, end, used, cc_share):
    """All derived columns for 'used' (% of the limit) and the Claude Code share (% of the use)."""
    r = {"limit_used_pct": fmt(used)}
    if end is None:
        return r
    start = end - dt.timedelta(days=WINDOW_DAYS)
    passed = min(max((now - start) / (end - start), 0.0), 1.0)
    costs = daily_costs()
    r.update(window_start=start.strftime(FMT), window_end=end.strftime(FMT), week_passed_pct=fmt(passed * 100))
    if costs:
        r["cost_window_usd"] = fmt(sum(k for d, k in costs.items() if start.date() <= d < now.date()), 2)
    for name, share in (("linear", passed), ("pattern", pattern_share(start, end, now, costs))):
        r["projection_" + name + "_pct"] = fmt(used / share) if share and share >= MIN_SHARE else ""
    if cc_share is not None:
        r.update(claude_code_share_pct=fmt(cc_share), claude_code_points=fmt(used * cc_share / 100),
                 other_points=fmt(used * (100 - cc_share) / 100))
    return r


# ── Usage endpoint ──────────────────────────────────────────────────────────────────────────
def user_agent():
    try:
        v = subprocess.run(["claude", "--version"], capture_output=True, text=True, timeout=20).stdout.split()[0]
        return "claude-code/" + v if re.fullmatch(r"\d+\.\d+\.\d+", v) else USER_AGENT_FALLBACK
    except (OSError, IndexError, subprocess.SubprocessError):
        return USER_AGENT_FALLBACK


def local_time(iso):
    """ISO time (UTC) -> naive local time; within 3 min of a full hour -> the full hour."""
    if not iso:
        return None
    t = dt.datetime.fromisoformat(iso).astimezone().replace(tzinfo=None, second=0, microsecond=0)
    full = (t + dt.timedelta(minutes=30)).replace(minute=0)
    return full if abs(full - t) <= dt.timedelta(minutes=3) else t


def read_api():
    """Query the usage endpoint -> dict used, session, end, cc_share, raw. Raises on any error."""
    token = json.loads(CREDENTIALS.read_text())["claudeAiOauth"]["accessToken"]
    req = urllib.request.Request(USAGE_URL, headers={"Authorization": "Bearer " + token, "anthropic-beta": USAGE_BETA,
                                                     "User-Agent": user_agent()})
    try:
        with urllib.request.urlopen(req, timeout=API_TIMEOUT_S) as f:
            d = json.load(f)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code}: {e.read()[:200].decode('utf-8', 'replace')}") from None
    week, sess = d.get("seven_day") or {}, d.get("five_hour") or {}
    used, session = week.get("utilization"), sess.get("utilization")
    if not isinstance(used, (int, float)):
        raise RuntimeError("answer without seven_day.utilization: " + json.dumps(d)[:300])
    parts = {r.get("key"): r for r in ((d.get("seven_day_breakdown") or {}).get("rows") or []) if isinstance(r, dict)}
    cc = (parts.get("claude_code") or {}).get("percent")
    raw = [f"API: week {used:g} % until {week.get('resets_at')}", f"session {session} % until {sess.get('resets_at')}"]
    raw += [f"{r.get('display_name', k)} {r.get('percent')} % ({r.get('percent_of_limit')} points)" for k, r in parts.items()]
    return {"used": float(used), "session": float(session) if isinstance(session, (int, float)) else None,
            "end": local_time(week.get("resets_at")), "cc_share": float(cc) if isinstance(cc, (int, float)) else None,
            "raw": " | ".join(raw)}


# ── Fallback: /usage in a separate tmux session ─────────────────────────────────────────────
def tmux(*args):
    return subprocess.run(["tmux", *args], capture_output=True, text=True, timeout=20).stdout


def screen():
    return tmux("capture-pane", "-p", "-J", "-t", TMUX_NAME)


def read_screen():
    """Start claude in its own tmux session, open /usage, return the screen text."""
    subprocess.run(["tmux", "new-session", "-d", "-s", TMUX_NAME, "-x", "160", "-y", "60", "-c", WORK_DIR, "claude"],
                   check=True, capture_output=True, timeout=20)
    try:
        until = time.time() + WAIT_START_S
        while time.time() < until and "❯" not in screen():
            time.sleep(2)
        if "❯" not in screen():
            raise RuntimeError("Claude does not start (no prompt): " + screen()[-300:])
        time.sleep(1)
        tmux("send-keys", "-t", TMUX_NAME, "/usage")
        time.sleep(1)
        tmux("send-keys", "-t", TMUX_NAME, "Enter")
        until = time.time() + WAIT_USAGE_S
        text = ""
        while time.time() < until:
            time.sleep(2)
            text = screen()
            if "Current week" in text and "% used" in text and "Scanning" not in text and "Loading" not in text:
                break
        time.sleep(1)
        return screen() or text
    finally:
        subprocess.run(["tmux", "kill-session", "-t", TMUX_NAME], capture_output=True)


def parse_screen(text, now):
    """-> (used %, session %, window end); missing parts None. Depends on the layout of /usage."""
    m = re.search(r"Current week \(all models\)\s*\n[^\n]*?(\d+(?:\.\d+)?)% used\s*\n\s*Resets ([A-Z][a-z]{2}) (\d{1,2}),? "
                  r"(\d{1,2})(?::(\d{2}))?\s*([ap]m)", text)
    used = end = None
    if m:
        used = float(m.group(1))
        h = int(m.group(4)) % 12 + (12 if m.group(6) == "pm" else 0)
        try:
            end = dt.datetime(now.year, MONTHS[m.group(2)], int(m.group(3)), h, int(m.group(5) or 0))
            if end < now - dt.timedelta(days=2):
                end = end.replace(year=now.year + 1)
            full = (end + dt.timedelta(minutes=30)).replace(minute=0)  # /usage rounds minutes down
            if abs(full - end) <= dt.timedelta(minutes=3):
                end = full
        except (KeyError, ValueError):
            end = None
    s = re.search(r"Current session\s*\n[^\n]*?(\d+(?:\.\d+)?)% used", text)
    return used, float(s.group(1)) if s else None, end


# ── One run ─────────────────────────────────────────────────────────────────────────────────
def row_from_api(now, rows, source, a, prefix=""):
    r = calc(now, a["end"] or window_end(now, rows), a["used"], a["cc_share"])
    r.update(date=now.strftime("%Y-%m-%d"), time=now.strftime("%H:%M"), source=source,
             session_pct=fmt(a["session"], 0), raw=(prefix + a["raw"])[:1500])
    return r


def read_once(source):
    """Endpoint -> else tmux /usage (refreshes the token) -> endpoint again -> else numbers from the screen."""
    now = dt.datetime.now().replace(second=0, microsecond=0)
    rows = read_rows()
    try:
        return row_from_api(now, rows, source, read_api())
    except Exception as e:  # noqa: BLE001 - endpoint gone or token expired -> fallback
        api_error = f"API ERROR: {e}"[:300].replace("\n", " ")
        log(api_error)
    text, tmux_error = None, ""
    try:
        text = read_screen()
    except Exception as e:  # noqa: BLE001
        tmux_error = f"TMUX ERROR: {e}"
        log(tmux_error)
    try:
        return row_from_api(now, rows, source, read_api(), prefix=api_error + " | 2nd try after tmux ok | ")
    except Exception as e:  # noqa: BLE001
        api_error += f" | 2nd try: {e}"[:300].replace("\n", " ")
    base = {"date": now.strftime("%Y-%m-%d"), "time": now.strftime("%H:%M"), "source": source}
    if text is None:
        return {**base, "raw": (api_error + " | " + tmux_error)[:900].replace("\n", " | ")}
    used, session, end = parse_screen(text, now)
    r = calc(now, end or window_end(now, rows), used, None) if used is not None else {}
    screen_text = " | ".join(x.strip() for x in text.splitlines() if x.strip() and not set(x.strip()) <= set("▔─ "))
    return {**r, **base, "session_pct": fmt(session, 0), "raw": (api_error + " | tmux: " + screen_text)[:1500]}


def summary(r):
    if not r.get("limit_used_pct"):
        return "Weekly limit could not be read (endpoint and /usage): " + r.get("raw", "")[:300]
    out = [f"{r['limit_used_pct']} % of the weekly limit used ({r.get('week_passed_pct') or '?'} % of the week passed)"]
    if r.get("session_pct"):
        out.append(f"session {r['session_pct']} %")
    if r.get("claude_code_share_pct"):
        out.append(f"Claude Code {r['claude_code_share_pct']} % of the use = {r['claude_code_points']} points, "
                   f"other {r['other_points']} points")
    if r.get("window_end"):
        out.append(f"projection to {r['window_end']}: linear {r.get('projection_linear_pct') or '-'} %, "
                   f"pattern {r.get('projection_pattern_pct') or '-'} %")
    return "\n".join(out)


def main():
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "read":
        r = read_once(sys.argv[2] if len(sys.argv) > 2 else "manual")
        write_row(r)
        log(f"read {r['source']}: used {r.get('limit_used_pct')} cc {r.get('claude_code_share_pct')} end {r.get('window_end')}")
        print(summary(r))
        sys.exit(0 if r.get("limit_used_pct") else 1)
    elif mode == "api":
        a = read_api()
        print(json.dumps({**a, "end": str(a["end"])}, ensure_ascii=False, indent=1))
    elif mode == "status":
        for r in read_rows()[-5:]:
            print({k: v for k, v in r.items() if k != "raw" and v})
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main()
