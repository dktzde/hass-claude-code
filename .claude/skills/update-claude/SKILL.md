---
name: update-claude
description: "Update the pinned Claude Code version in this Home Assistant add-on fork, bump the add-on version, test-build, commit and push. Use when the user asks to update Claude Code in the add-on."
argument-hint: "[version]  (optional, defaults to latest)"
disable-model-invocation: true
---

# Update Claude Code in the add-on

Claude Code is pinned via `ARG CLAUDE_CODE_VERSION` in `addon/Dockerfile`. The HA Supervisor builds with Docker layer cache, so only a changed pin makes it install a new version. Follow these steps in order and stop to report if any step fails.

System packages and docs are refreshed only by the GitHub Action (it needs a fresh build to read the package versions); never edit `PACKAGES_STAMP`, `DOCS_STAMP` or `addon/packages.txt` by hand.

The GitHub Action `.github/workflows/update-claude-code.yml` runs steps 1 and 3–5 automatically every Saturday 05:47 UTC (07:47 CEST / 06:47 CET) and opens one issue per source for new commits from steps 2/2a. It may have pushed since the last local pull, so run `git pull origin main` first.

## 1. Determine versions

- Current pin: `grep -n "ARG CLAUDE_CODE_VERSION" addon/Dockerfile`
- Target: `$ARGUMENTS` if given, otherwise latest:
  `curl -s https://registry.npmjs.org/@anthropic-ai/claude-code/latest | grep -o '"version":"[^"]*"'`
- Verify the release exists: `curl -sI https://downloads.claude.ai/claude-code-releases/<VERSION>/manifest.json | head -1` must be `200`.
- If target equals current pin: tell the user Claude Code is already up to date, still run steps 2 and 2a, and skip step 3's version edits unless fixes were taken (then bump only the add-on version and changelog).

## 2. Sync with upstream first

- `git fetch upstream` and check `git log --oneline HEAD..upstream/main`.
- If upstream has new commits, show them to the user and ask whether to merge them before continuing. Do not merge without confirmation.

## 2a. Check the YangXu1990uiuc fork

Our pnpm-11 and login-persistence fixes came from this fork. Check it for new fixes worth taking.

- Remote `yangxu` (add if missing: `git remote add yangxu https://github.com/YangXu1990uiuc/hass-claude-code.git`), then `git fetch yangxu`.
- Last reviewed commit: `3735681`
- New since then: `git log --format='%h %ad %s' --date=short 3735681..yangxu/main`, also glance at new branches in `git branch -r | grep yangxu`.
- If there are new commits: summarize each (what it fixes, whether relevant for us) and ask the user which to cherry-pick with `git cherry-pick -x <hash>`. Do not cherry-pick without confirmation.
- Afterwards, whether or not anything was taken, update the "Last reviewed commit" hash above to the current `yangxu/main` and include SKILL.md in the commit.

## 3. Edit

- `addon/Dockerfile`: set `ARG CLAUDE_CODE_VERSION=<VERSION>`
- `addon/config.yaml`: bump `version` patch level (e.g. 0.1.12 -> 0.1.13) — without this HA offers no update
- `addon/CHANGELOG.md`: add a new top section `## <new add-on version>` with `- Update Claude Code to <VERSION>`
- `README.md`: update the "currently **x.y.z**" version in the fork note at the top

## 4. Test-build (amd64)

```bash
cd addon && docker buildx build . --pull --platform linux/amd64 --load -t hass-claude-code-test:local
docker run --rm --entrypoint /root/.local/bin/claude hass-claude-code-test:local --version
docker rmi hass-claude-code-test:local
```

Run the build in the background (takes several minutes). The version output must match `<VERSION>`. If the build fails, report the error and do not commit.

## 5. Commit and push

```bash
git add addon/Dockerfile addon/config.yaml addon/CHANGELOG.md README.md .claude/skills/update-claude/SKILL.md
git commit -m "chore(addon): update Claude Code to <VERSION>"
git push origin HEAD:main
```

Push uses the token in `~/.git-credentials`. Never print the token.

## 6. Tell the user

One short message in German: new Claude Code version, new add-on version, and that in HA they go to **Add-on Store → ⋮ → Nach Updates suchen**, then **Update** on the add-on.
