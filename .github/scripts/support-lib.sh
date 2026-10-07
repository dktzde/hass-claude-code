# shellcheck shell=bash
# Helpers for the support dates in the report issues.
# EOL_API and TODAY can be overridden for tests.
EOL_API=${EOL_API:-https://endoflife.date/api}
TODAY=${TODAY:-$(date -u +%F)}

# days_left YYYY-MM-DD: days from TODAY until the date (negative when past)
days_left() {
  echo $(( ( $(date -u -d "$1" +%s) - $(date -u -d "$TODAY" +%s) ) / 86400 ))
}

# de_date YYYY-MM-DD: "01.11.2027 (noch 389 Tage)" or "... (seit 12 Tagen vorbei)"
de_date() {
  local days
  days=$(days_left "$1")
  if [ "$days" -ge 0 ]; then
    printf '%s (noch %d Tage)' "$(date -u -d "$1" +%d.%m.%Y)" "$days"
  else
    printf '%s (**seit %d Tagen vorbei**)' "$(date -u -d "$1" +%d.%m.%Y)" "$(( -days ))"
  fi
}

# eol_json PRODUCT: the endoflife.date cycles of a product, empty on failure
eol_json() {
  curl -fsSL "$EOL_API/$1.json" 2>/dev/null || true
}

# eol_field JSON CYCLE FIELD: a date field of one cycle, empty when unknown
# (endoflife.date uses true/false instead of a date when there is none)
eol_field() {
  jq -r --arg c "$2" --arg f "$3" \
    '.[]? | select(.cycle == $c) | .[$f] | select(type == "string")' <<< "$1" 2>/dev/null | head -1
}
