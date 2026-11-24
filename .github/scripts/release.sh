#!/usr/bin/env bash
# Publishes a GitHub release for the app version in addon/config.yaml, with
# its entry from addon/CHANGELOG.md as the notes, unless that release exists.
# Home Assistant does not need releases (the Supervisor builds the app from
# main); they show the current version on the repository page and notify
# people who watch the repository for releases.
#
# Usage: release.sh <commit>   tag the given commit (on main) as v<version>
# With DRY_RUN=1 it only prints what it would publish.
# Needs GH_TOKEN and GH_REPO for gh.
set -euo pipefail
target=$1

version=$(awk '/^version:/ { print $2; exit }' addon/config.yaml)
tag="v$version"

if gh release view "$tag" > /dev/null 2>&1; then
  echo "Release $tag exists already."
  exit 0
fi

# The entry under "## <version>" up to the next "## " heading, without the
# heading itself (the release title is the version)
notes=$(awk -v heading="## $version" '
  $0 == heading { found = 1; next }
  found && /^## / { exit }
  found { print }
' addon/CHANGELOG.md | sed -e '/./,$!d')
if [ -z "$notes" ]; then
  echo "::error::No entry \"## $version\" in addon/CHANGELOG.md"
  exit 1
fi
notes=$(printf '%s\n\n---\n\nHome Assistant builds the app on your device from this repository and offers this version as an app update. There is nothing to download here.\n' "$notes")

if [ "${DRY_RUN:-}" = 1 ]; then
  printf 'Would publish release %s on %s with these notes:\n\n%s\n' "$tag" "$target" "$notes"
  exit 0
fi

gh release create "$tag" --target "$target" --title "$version" --notes "$notes"
echo "Published release $tag."
