#!/usr/bin/env bash
# Prints the body of the npm issue, or nothing when no dependency of the MCP
# server has a new major version. Run from the repo root. Needs curl and jq;
# NPM_REGISTRY and TODAY can be overridden for tests.
#
# npm packages publish no end-of-support dates. As the best available measure
# this shows, per installed release line, the date of its last update and
# whether it still gets updates since the next major version came out.
set -euo pipefail
source "$(dirname "$0")/support-lib.sh"
registry=${NPM_REGISTRY:-https://registry.npmjs.org}
dir=addon/mcp-server

# installed NAME: version of a direct dependency in the lockfile (no peer suffix)
installed() {
  awk -v a="      $1:" -v b="      '$1':" '
    /^importers:/ { on = 1 } /^packages:/ { on = 0 }
    on && ($0 == a || $0 == b) { found = 1; next }
    found && /^        version:/ { sub(/\(.*/, "", $2); print $2; exit }
  ' "$dir/pnpm-lock.yaml"
}

# line_of VERSION: the release line caret ranges stay in ("3." for 3.x, "0.1." for 0.1.x)
line_of() {
  if [ "${1%%.*}" = 0 ]; then echo "$(cut -d. -f1-2 <<< "$1")."; else echo "${1%%.*}."; fi
}

# releases DOC PREFIX first|last: "version date" of the first/last stable release of a line
releases() {
  jq -r --arg p "$2" --arg which "$3" '
    def ver: split(".") | map(tonumber);
    [.time | to_entries[] | select(.key | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) | select(.key | startswith($p))]
    | sort_by(.key | ver) | (if $which == "first" then first else last end)
    | select(. != null) | "\(.key) \(.value[0:10])"' <<< "$1"
}

# successor DOC VERSION: "version date" of the first stable release of the next
# line after the one VERSION is on (the major after it, or the minor for 0.x)
successor() {
  jq -r --arg v "$2" '
    def ver: split(".") | map(tonumber);
    ($v | ver) as $i
    | [.time | to_entries[] | select(.key | test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))
       | select((.key | ver) as $k
           | if $i[0] == 0 then ($k[0] > 0 or $k[1] > $i[1]) else $k[0] > $i[0] end)]
    | sort_by(.key | ver) | first | select(. != null) | "\(.key) \(.value[0:10])"' <<< "$1"
}

outdated=()
current=()
failed=0
while read -r name range; do
  version=$(installed "$name")
  doc=$(curl -fsSL "$registry/$name" 2>/dev/null || true)
  latest=$(jq -r '."dist-tags".latest // empty' <<< "$doc" 2>/dev/null || true)
  if [ -z "$version" ] || [ -z "$latest" ]; then
    echo "::warning::Could not look up $name (installed: ${version:-?})" >&2
    failed=$(( failed + 1 ))
    continue
  fi
  line=$(line_of "$version")
  read -r line_last line_last_date < <(releases "$doc" "$line" last) || true
  entry="\`$name\` $version (erlaubt \`$range\`)"
  if [ "$(line_of "$latest")" = "$line" ]; then
    current+=("- $entry: neueste Hauptlinie ${line}x, letztes Update $line_last am $(date -u -d "$line_last_date" +%d.%m.%Y)")
    continue
  fi
  read -r next_first next_date < <(successor "$doc" "$version") || true
  if [[ "$line_last_date" > "$next_date" ]]; then
    status="Linie ${line}x bekommt noch Updates, zuletzt $line_last am $(date -u -d "$line_last_date" +%d.%m.%Y)"
  else
    status="Linie ${line}x bekommt **keine Updates mehr**, seit $next_first am $(date -u -d "$next_date" +%d.%m.%Y) erschien (letztes Update $line_last am $(date -u -d "$line_last_date" +%d.%m.%Y))"
  fi
  outdated+=("- $entry: neue Hauptversion $latest. $status")
done < <(jq -r '(.dependencies + .devDependencies) | to_entries[] | "\(.key) \(.value)"' "$dir/package.json")

# Fail instead of printing nothing, which would close an open issue
if [ "${#outdated[@]}" -eq 0 ] && [ "$failed" -gt 0 ]; then
  echo "::error::$failed npm lookups failed; not updating the issue" >&2
  exit 1
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### npm dependencies"
    if [ "${#outdated[@]}" -gt 0 ]; then printf '%s\n' "${outdated[@]}"; fi
    if [ "${#current[@]}" -gt 0 ]; then printf '%s\n' "${current[@]}"; fi
  } >> "$GITHUB_STEP_SUMMARY"
fi

[ "${#outdated[@]}" -gt 0 ] || exit 0

cat << EOF
Für diese npm-Pakete des MCP-Servers gibt es neue Hauptversionen:

$(printf '%s\n' "${outdated[@]}")

Die übrigen Pakete sind auf der neuesten Hauptlinie:

$(if [ "${#current[@]}" -gt 0 ]; then printf '%s\n' "${current[@]}"; else echo "- keine"; fi)

## Zum Support

npm-Pakete veröffentlichen kein festes Support-Ende. Als Maßstab steht oben, ob die installierte Linie noch Updates bekommt und wann zuletzt. Eine Linie ohne Updates bekommt auch keine Sicherheitskorrekturen mehr.

## Was zu tun ist

Kleine Updates innerhalb der erlaubten Hauptversion übernimmt die wöchentliche Action „Update add-on“ automatisch. Hauptversionen können Code-Änderungen brauchen und werden deshalb nur gemeldet.

Zum Übernehmen: Version in \`addon/mcp-server/package.json\` anheben, das Lockfile mit pnpm 11 neu erzeugen (\`pnpm install --lockfile-only\`), Code anpassen, Testbuild.
EOF
