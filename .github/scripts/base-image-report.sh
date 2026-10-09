#!/usr/bin/env bash
# Prints the body of the base image issue, or nothing when there is nothing to
# do: no newer base image and no support end coming up. Run from the repo root.
# Needs gh (GH_TOKEN), curl and jq; NOTICE_DAYS_MAIN/COMMUNITY can be overridden.
set -euo pipefail
source "$(dirname "$0")/support-lib.sh"
notice_main=${NOTICE_DAYS_MAIN:-90}
notice_community=${NOTICE_DAYS_COMMUNITY:-30}

# The current Supervisor builder only reads the Dockerfile (build.yaml is kept
# in sync for older Supervisors)
current=$(grep -oP '^ARG BUILD_FROM=ghcr.io/hassio-addons/base:\K\S+' addon/Dockerfile)
builder=$(grep -oP '^FROM alpine:\K\S+(?= AS mcp-builder)' addon/Dockerfile)
alpine=$(grep -oP '^alpine-release-\K[0-9]+\.[0-9]+' addon/packages.txt 2>/dev/null || echo "$builder")
python=$(grep -oP '^python3-\K[0-9]+\.[0-9]+' addon/packages.txt 2>/dev/null || true)
node=$(grep -oP '^nodejs-\K[0-9]+' addon/packages.txt 2>/dev/null || true)

# --- Newer base image? ---
newer=false
latest_line="- Latest version: unknown (lookup failed)"
if read -r tag url < <(gh release view --repo hassio-addons/app-base --json tagName,url \
                         --jq '"\(.tagName) \(.url)"' 2>/dev/null) &&
   [[ "${tag#v}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  latest=${tag#v}
  if [ "$latest" != "$current" ] && [ "$(printf '%s\n' "$current" "$latest" | sort -V | tail -1)" = "$latest" ]; then
    newer=true
    new_alpine=$(docker run --rm --entrypoint cat "ghcr.io/hassio-addons/base:$latest" /etc/alpine-release 2>/dev/null || echo unknown)
    if [ "$new_alpine" = unknown ]; then change="unknown"
    elif [ "${new_alpine%.*}" = "$alpine" ]; then change="no, stays $alpine"
    else change="**yes**, $alpine → ${new_alpine%.*}"; fi
    latest_line="- Latest version: \`$latest\` (Alpine \`$new_alpine\`), [release notes]($url)
- Changes the Alpine version: $change"
  else
    latest_line="- Latest version: \`$latest\`, there is no newer one"
  fi
else
  # Fail instead of printing nothing, which would close an open issue
  echo "::error::Could not read the latest hassio-addons/app-base release" >&2
  exit 1
fi

# --- Support of the installed Alpine version ---
# main gets security fixes until its end of life; community only until the
# next stable Alpine release.
alerts=()
alpine_json=$(eol_json alpine-linux)
if [ -z "$alpine_json" ]; then
  echo "::error::Could not read the Alpine support dates from $EOL_API" >&2
  exit 1
fi
release=$(eol_field "$alpine_json" "$alpine" releaseDate)
main_eol=$(eol_field "$alpine_json" "$alpine" eol)
next="${alpine%%.*}.$(( ${alpine#*.} + 1 ))"
community_eol=$(eol_field "$alpine_json" "$next" releaseDate)
community_note=""
if [ -z "$community_eol" ] && [ -n "$release" ]; then
  community_eol=$(date -u -d "$release +6 months" +%F)
  community_note=", estimated: Alpine $next is not out yet"
fi
if [ -n "$main_eol" ]; then
  main_line=$(fmt_date "$main_eol")
  [ "$(days_left "$main_eol")" -le "$notice_main" ] && alerts+=("main repository")
else
  main_line="unknown"
fi
if [ -n "$community_eol" ]; then
  community_line="$(fmt_date "$community_eol")$community_note"
  [ "$(days_left "$community_eol")" -le "$notice_community" ] && alerts+=("community repository")
else
  community_line="unknown"
fi

runtime_line() { # PRODUCT CYCLE LABEL
  local eol
  [ -n "$2" ] || return 0
  eol=$(eol_field "$(eol_json "$1")" "$2" eol)
  if [ -n "$eol" ]; then eol=$(fmt_date "$eol"); else eol=unknown; fi
  printf -- '- %s %s: supported until %s\n' "$3" "$2" "$eol"
}

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Base image"
    echo "Installed $current (Alpine $alpine), newer available: $newer"
    echo "Alpine $alpine main until ${main_eol:-?}, community until ${community_eol:-?}"
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$newer" = false ] && [ "${#alerts[@]}" -eq 0 ]; then
  exit 0
fi

reason=""
waiting=""
if [ "$newer" = true ]; then
  reason="There is a new version of the base image."
else
  waiting="There is no newer base image yet. This issue is updated every week and shows the new version as soon as one comes out."
fi
if [ "${#alerts[@]}" -gt 0 ]; then
  reason="${reason:+$reason }Support of the installed Alpine version ends soon or has ended ($(IFS=,; echo "${alerts[*]}" | sed 's/,/, /g'))."
fi

cat << EOF
$reason

## Base image \`ghcr.io/hassio-addons/base\`

- Installed: \`$current\` (Alpine \`$alpine\`)
$latest_line

## Support of the installed version

- Alpine $alpine, main repository, for example Python, Node.js, curl, git: updates until $main_line
- Alpine $alpine, community repository, for example ttyd, ripgrep: updates until $community_line
$(runtime_line python "$python" Python)
$(runtime_line nodejs "$node" Node.js)

The community repository only gets updates until the next Alpine release, the main repository for about two years. Source: [endoflife.date](https://endoflife.date/alpine-linux).

## What to do

${waiting:+$waiting

}The switch is deliberately not automatic. A new Alpine version often brings new versions of Python and Node.js, and the builder stage must use the same Alpine version, or the native module better-sqlite3 does not match the Node.js in the add-on.

- Set \`ARG BUILD_FROM\` in \`addon/Dockerfile\` to the new version, and \`addon/build.yaml\` (both architectures) to match
- For a new Alpine version: change \`FROM alpine:…\` of the builder stage in \`addon/Dockerfile\`
- Add-on version in \`addon/config.yaml\` and \`addon/CHANGELOG.md\`

Then test: on a branch, start the Action "Update add-on" by hand (Run workflow → choose the branch). Runs on branches other than main are test runs and never publish anything.
EOF
