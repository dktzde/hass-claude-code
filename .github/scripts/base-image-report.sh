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
latest_line="- Neueste Version: unbekannt (Abfrage fehlgeschlagen)"
if read -r tag url < <(gh release view --repo hassio-addons/app-base --json tagName,url \
                         --jq '"\(.tagName) \(.url)"' 2>/dev/null) &&
   [[ "${tag#v}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  latest=${tag#v}
  if [ "$latest" != "$current" ] && [ "$(printf '%s\n' "$current" "$latest" | sort -V | tail -1)" = "$latest" ]; then
    newer=true
    new_alpine=$(docker run --rm --entrypoint cat "ghcr.io/hassio-addons/base:$latest" /etc/alpine-release 2>/dev/null || echo unbekannt)
    if [ "$new_alpine" = unbekannt ]; then change="unbekannt"
    elif [ "${new_alpine%.*}" = "$alpine" ]; then change="nein, bleibt $alpine"
    else change="**ja**, $alpine → ${new_alpine%.*}"; fi
    latest_line="- Neueste Version: \`$latest\` (Alpine \`$new_alpine\`), [Release notes]($url)
- Wechselt die Alpine-Version: $change"
  else
    latest_line="- Neueste Version: \`$latest\`, es gibt keine neuere"
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
  community_note=", geschätzt: Alpine $next ist noch nicht erschienen"
fi
if [ -n "$main_eol" ]; then
  main_line=$(de_date "$main_eol")
  [ "$(days_left "$main_eol")" -le "$notice_main" ] && alerts+=("Hauptrepository")
else
  main_line="unbekannt"
fi
if [ -n "$community_eol" ]; then
  community_line="$(de_date "$community_eol")$community_note"
  [ "$(days_left "$community_eol")" -le "$notice_community" ] && alerts+=("Community-Repository")
else
  community_line="unbekannt"
fi

runtime_line() { # PRODUCT CYCLE LABEL
  local eol
  [ -n "$2" ] || return 0
  eol=$(eol_field "$(eol_json "$1")" "$2" eol)
  if [ -n "$eol" ]; then eol=$(de_date "$eol"); else eol=unbekannt; fi
  printf -- '- %s %s: Support bis %s\n' "$3" "$2" "$eol"
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
  reason="Es gibt eine neue Version des Basis-Images."
else
  waiting="Ein neueres Basis-Image gibt es noch nicht. Dieses Issue wird jede Woche aktualisiert. Sobald eins erscheint, steht es hier."
fi
if [ "${#alerts[@]}" -gt 0 ]; then
  reason="${reason:+$reason }Der Support der installierten Alpine-Version endet bald oder ist vorbei ($(IFS=,; echo "${alerts[*]}" | sed 's/,/, /g'))."
fi

cat << EOF
$reason

## Basis-Image \`ghcr.io/hassio-addons/base\`

- Installiert: \`$current\` (Alpine \`$alpine\`)
$latest_line

## Support der installierten Version

- Alpine $alpine, Hauptrepository (main), zum Beispiel Python, Node.js, curl, git: Updates bis $main_line
- Alpine $alpine, Community-Repository, zum Beispiel ttyd, ripgrep: Updates bis $community_line
$(runtime_line python "$python" Python)
$(runtime_line nodejs "$node" Node.js)

Das Community-Repository bekommt nur Updates bis zur nächsten Alpine-Version, das Hauptrepository rund zwei Jahre. Quelle: [endoflife.date](https://endoflife.date/alpine-linux).

## Was zu tun ist

${waiting:+$waiting

}Der Wechsel passiert bewusst nicht automatisch. Mit einer neuen Alpine-Version ändern sich oft die Versionen von Python und Node.js, und die Builder-Stage muss dieselbe Alpine-Version nutzen, sonst passt das native Modul better-sqlite3 nicht zum Node.js im Add-on.

- \`ARG BUILD_FROM\` in \`addon/Dockerfile\` auf die neue Version setzen, \`addon/build.yaml\` (beide Architekturen) gleich mitziehen
- Bei neuer Alpine-Version: \`FROM alpine:…\` der Builder-Stage in \`addon/Dockerfile\` anpassen
- Add-on-Version in \`addon/config.yaml\` und \`addon/CHANGELOG.md\`

Danach testen: auf einem Branch die Action „Update add-on“ manuell starten (Run workflow → Branch auswählen). Läufe auf anderen Branches als main sind reine Testläufe und veröffentlichen nichts.
EOF
