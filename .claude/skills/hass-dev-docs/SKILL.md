---
name: hass-dev-docs
description: "Home Assistant developer documentation. Use when the user asks about Home Assistant integrations, add-ons, architecture, APIs, entities, config flows, or any HA development topic. Also use when explicitly asked to update or search HA developer docs."
argument-hint: "[update [user|developer|both]|search <query> [in user|developer]]"
allowed-tools: Bash(python3 *), Bash(rg *), Task(hass-docs-search)
---

# Home Assistant Developer Docs

This skill manages local mirrors of the Home Assistant documentation as plain markdown and searches them with ripgrep (`rg`). There is no search service and nothing to install or start.

- Developer docs: `docs/hass-developer/` (relative to the project root)
- User docs: `docs/hass-user/`
- Each folder has a `CLAUDE.md` index with one line per file.

## Commands

### `/hass-dev-docs update [user|developer|both]`

Update the local docs mirror from the upstream GitHub repositories. Developer docs are the default.

```bash
# Developer docs
python3 .claude/skills/hass-dev-docs/scripts/update-docs.py docs/hass-developer
# User docs
python3 .claude/skills/hass-dev-docs/scripts/update-user-docs.py docs/hass-user
```

Each script will:
1. Clone the latest docs from GitHub
2. Strip YAML frontmatter (extracting only the title)
3. Remove MDX components and raw HTML
4. Remove Docusaurus admonition markers (keeping content)
5. Generate a `CLAUDE.md` index
6. Generate `CHANGELOG.md` with diff summary
7. Deploy the clean versions

The weekly workflow `.github/workflows/update-claude-code.yml` runs both scripts on its own, so a manual update is rarely needed. Report the result to the user: summarize what changed based on the script output.

### `/hass-dev-docs search <query> [in user|developer]`

Search the docs for a topic. Default: both doc sets; `in user` or `in developer` limits the search to one.

Delegate to the subagent, so the search results do not fill the main context:

```
Use Task tool with:
- subagent_type: hass-docs-search
- prompt: Search for "<user's query>" [in user docs|in developer docs|in both user and developer docs].
```

The subagent searches the `CLAUDE.md` indexes and the file contents with `rg`, reads the relevant files and returns a summary with file paths.

### `/hass-dev-docs` (no arguments)

Check whether `docs/hass-developer/CLAUDE.md` exists:
- If it exists, read it and use it as context for answering HA development questions
- If not, tell the user to run `/hass-dev-docs update` first

## Answering HA questions

When this skill is loaded to answer a question (not via an explicit `/` command), delegate to `hass-docs-search` as above and answer with specific file references.

## Notes

- The docs are plain markdown files, no build step
- The update scripts work through a staging directory and are safe to re-run
- The add-on has its own keyword search over the same docs (`search_docs` in `addon/mcp-server/`); this skill is only for working on this repository and in other repos next to it
