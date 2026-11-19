#!/usr/bin/env python3
"""Home Assistant command_line sensor: Claude Code costs and the weekly limit as JSON (see ha_package.yaml).

Reads claude_token_usage.csv (token_daily_stats.js) and weekly_limit.csv (weekly_limit.py) and prints:
  last_day          last day in the daily CSV (= sensor state)
  day, day_before   cost of the last day and of the day before
  week, month       cost of the 7 and 30 days up to last_day
  month_by_model    cost of the 30 days per model
  weekly            latest row of weekly_limit.csv (used %, session %, Claude Code share, projections, window end, time)
All costs at Claude API list prices, converted with <rate> (default 1 = USD).

Usage: python3 costs_sensor.py [rate] [data dir]
"""
import csv
import datetime as dt
import json
import sys
from pathlib import Path

CSV_DELIMITER = ","  # must match the setting in token_daily_stats.js and weekly_limit.py


def number(s):
    try:
        return float((s or "0").replace(",", "."))
    except ValueError:
        return 0.0


def read(path):
    try:
        with open(path, newline="", encoding="utf-8") as f:
            return list(csv.DictReader(f, delimiter=CSV_DELIMITER))
    except OSError:
        return []


def main():
    rate = float(sys.argv[1]) if len(sys.argv) > 1 else 1.0
    data = Path(sys.argv[2] if len(sys.argv) > 2 else "/share/claude_usage")
    per_day, per_model = {}, {}
    rows = read(data / "claude_token_usage.csv")
    for r in rows:
        per_day[r["date"]] = per_day.get(r["date"], 0.0) + number(r.get("cost_usd")) * rate
    weekly = (read(data / "weekly_limit.csv") or [{}])[-1]
    weekly = {k: weekly.get(k) for k in ("date", "time", "limit_used_pct", "session_pct", "claude_code_share_pct",
                                         "week_passed_pct", "projection_linear_pct", "projection_pattern_pct", "window_end")}
    if not per_day:  # new installation: no finished day yet, but the weekly limit may already be there
        print(json.dumps({"ok": False, "error": "no daily CSV rows yet", "rate": rate, "weekly": weekly}))
        return
    last = dt.date.fromisoformat(max(per_day))
    days = [(last - dt.timedelta(days=i)).isoformat() for i in range(30)]
    for r in rows:
        if r["date"] in days:
            per_model[r["model"]] = per_model.get(r["model"], 0.0) + number(r.get("cost_usd")) * rate
    print(json.dumps({
        "ok": True, "last_day": last.isoformat(), "rate": rate,
        "day": round(per_day.get(days[0], 0.0), 2), "day_before": round(per_day.get(days[1], 0.0), 2),
        "week": round(sum(per_day.get(d, 0.0) for d in days[:7]), 2),
        "month": round(sum(per_day.get(d, 0.0) for d in days), 2),
        "month_by_model": {k: round(v, 2) for k, v in sorted(per_model.items(), key=lambda x: -x[1])},
        "weekly": weekly,
    }))


main()
