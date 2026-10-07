# shellcheck shell=bash
# sync_issue TITLE BODY [CLOSE_COMMENT]
# Keeps one open issue per title: created or refreshed while BODY is not
# empty, closed once it is. Needs GH_REPO and GH_TOKEN.
sync_issue() {
  local title=$1 body=$2 close_comment=${3:-Erledigt.} number
  number=$(gh issue list --state open --limit 100 --json number,title \
    --jq ".[] | select(.title == \"$title\") | .number" | head -1)
  if [ -z "$body" ]; then
    if [ -n "$number" ]; then gh issue close "$number" --comment "$close_comment"; fi
    return 0
  fi
  if [ -n "$number" ]; then
    gh issue edit "$number" --body "$body"
  else
    gh issue create --title "$title" --body "$body"
  fi
}
