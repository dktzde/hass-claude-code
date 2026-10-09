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
# @types/node follows the Node.js major the add-on runs (Alpine's nodejs
# package), not the latest @types/node: see MAINTENANCE.md
node_major=$(grep -oP '^nodejs-\K[0-9]+' addon/packages.txt 2>/dev/null || true)

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
  entry="\`$name\` $version (allowed \`$range\`)"
  if [ "$name" = @types/node ] && [ -n "$node_major" ] && [ "${latest%%.*}" != "$node_major" ]; then
    if [ "${version%%.*}" = "$node_major" ]; then
      current+=("- $entry: matches Node.js $node_major in the add-on image (the latest major $latest is for a newer Node.js), last update $line_last on $line_last_date")
    else
      outdated+=("- $entry: the add-on image runs Node.js $node_major, so set \`^$node_major.0.0\` (not the latest major $latest)")
    fi
    continue
  fi
  if [ "$(line_of "$latest")" = "$line" ]; then
    current+=("- $entry: latest major line ${line}x, last update $line_last on $line_last_date")
    continue
  fi
  read -r next_first next_date < <(successor "$doc" "$version") || true
  if [[ "$line_last_date" > "$next_date" ]]; then
    status="Line ${line}x still gets updates, last $line_last on $line_last_date"
  else
    status="Line ${line}x gets **no more updates** since $next_first came out on $next_date (last update $line_last on $line_last_date)"
  fi
  outdated+=("- $entry: new major version $latest. $status")
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
These npm packages of the MCP server have new major versions:

$(printf '%s\n' "${outdated[@]}")

The other packages are on the latest major line:

$(if [ "${#current[@]}" -gt 0 ]; then printf '%s\n' "${current[@]}"; else echo "- none"; fi)

## About support

npm packages publish no fixed end of support. As a measure, the list above shows whether the installed line still gets updates and when it got the last one. A line without updates gets no security fixes either.

## What to do

The weekly Action "Update add-on" takes over minor updates within the allowed major version automatically. Major versions can need code changes, so they are only reported.

To take one over: raise the version in \`addon/mcp-server/package.json\`, regenerate the lockfile with pnpm 11 (\`pnpm install --lockfile-only\`), adapt the code, test-build.
EOF
