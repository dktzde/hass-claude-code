# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Start here: current state and next steps

**Read [`STATUS.md`](STATUS.md) first.** It holds the current state, open decisions, the next steps and the conventions of this repository. Update it after every step, so the next session can continue without the chat history.

## Git, commits and pull requests

These rules apply to every session, also to Claude Code on the web.

- **Author:** commits and PRs must look as if the maintainer made them alone. Before the first commit run `git config user.name "dktzde"` and `git config user.email "dktzde@users.noreply.github.com"`. No `Co-Authored-By`, no "Generated with Claude" in commits, PR texts, issues, changelog or README.
- **Branches:** no `claude/` prefix where the environment allows it (Claude Code on the web may force `claude/…`; that is accepted).
- **One topic = one branch = one PR.** One commit per sub-topic, test after each commit. Plan the commit split before the first push. Never force-push a pushed branch; fix mistakes with `git revert`.
- **This is a fork of `dkmaker/hass-claude-code`.** Open PRs against our fork with `gh pr create --repo dktzde/hass-claude-code --base main`, otherwise they land at the upstream. Branches for PRs to the upstream start from `upstream/main`, use only `## Unreleased` in the changelog and never contain `STATUS.md` or `CLAUDE.md`. PRs to the upstream only after a test on the real device and explicit approval by the maintainer.
- **CodeRabbit:** this repository has fewer than 10 stars, so CodeRabbit does not review PRs automatically. Right after opening a PR that changes code (TypeScript, shell/s6 scripts, `Dockerfile`, workflows, `config.yaml`/`build.yaml`), comment `@coderabbitai review` (`gh pr comment <number> --repo dktzde/hass-claude-code --body "@coderabbitai review"`). Skip documentation-only PRs (`docs:`), drafts and pure version bumps without code changes. Before the merge, read the bot's comments and either address them or explain in the PR why not. Settings are in `.coderabbit.yaml`.
- **Merge** only when the maintainer explicitly asks, always with a merge commit (no squash), so every commit can be reverted on its own.
- **Versions:** bump only for user-facing changes and only on our `main`; documentation-only changes get no new version. Change the version everywhere at the same time.
- **Changelog:** every version gets its date as `<sub>YYYY-MM-DD</sub>` under its heading. Versions by earlier authors are separated by a `---` line and a bold sentence naming them.
- **Language:** everything in the repository is English (code, comments, docs, commits, PR and issue texts). Commit messages in the imperative, e.g. `feat(scope): …`, `fix: …`, `docs: …`, `chore: …`, `ci: …`; in PRs to the upstream follow its style.
- **No secrets or private data** (tokens, passwords, IP addresses, radio addresses, serial numbers, entity IDs) in the repository; use placeholders.
- **README:** a credit line for Claude Code only after asking the maintainer. It always links to the maintainer's add-on [hass-claude-code](https://github.com/dktzde/hass-claude-code) as well as to Claude Code.
- **License:** with every PR, remind the maintainer if `LICENSE` is missing or the copyright line does not name `dktzde` (keep the lines of earlier authors). Do not change the license without asking; a license change is its own PR on our `main`.
- **Handover:** keep `STATUS.md` (create it if missing) with the current state, next steps, known issues, decisions and key files. Record what runs on the device with date and time, what was checked and what not. Update it after every step.

## Home Assistant add-on (`addon/`)

The main product of this fork: a Home Assistant add-on that runs Claude Code with a web terminal (ttyd + tmux via Ingress) and a built-in MCP server (`addon/mcp-server/`) for Home Assistant APIs and docs search. The Supervisor builds the image on the user's device with the Docker layer cache, so everything that must update is pinned in `addon/Dockerfile` and refreshed by the weekly workflow `.github/workflows/update-claude-code.yml` (helper scripts in `.github/scripts/`). Never edit `PACKAGES_STAMP`, `DOCS_STAMP` or `addon/packages.txt` by hand. Details are in `STATUS.md` and `README.md`. Before a base image switch or an npm major update, read [`MAINTENANCE.md`](MAINTENANCE.md) (checklists and pitfalls), and add what you learn to it.

The rest of this file describes the docs tooling used during development.

## Docs tooling overview

This repository also provides Claude Code with Home Assistant documentation search capabilities. It contains:

- **Local doc mirrors** of HA user and developer documentation (cleaned markdown)
- **A semantic search service** for querying those docs via vector + keyword search
- **Claude Code skills and agents** that wire everything together

The goal: when working on HA integrations in other repos, Claude Code can search these docs via the `hass-dev-docs` skill or `hass-docs-search` subagent.

## Architecture

```
.claude/
  agents/
    hass-docs-search.md    # Haiku subagent — searches docs via the HTTP service
  skills/
    hass-dev-docs/
      SKILL.md             # Skill definition (update, index, search, stats, stop)
      scripts/             # Python scripts to clone + clean docs from GitHub
      service/             # Node.js search service (Express + SQLite + vector search)
docs/
  hass-developer/          # Cleaned HA developer docs (markdown), auto-generated
  hass-user/               # Cleaned HA user docs (markdown), auto-generated
resources/                 # Cloned upstream repos (gitignored, re-downloadable)
```

### Search service (`service/`)

TypeScript service running on Node.js via tsx. Key modules:

- `server.ts` — Express HTTP server, binds a dynamic port
- `db.ts` — SQLite database init (better-sqlite3 + sqlite-vec extension)
- `indexer.ts` — Reads markdown files, chunks by `##` headings, stores embeddings
- `embeddings.ts` — Loads Xenova/all-MiniLM-L6-v2 via @huggingface/transformers
- `search.ts` — Semantic (vector) and keyword (FTS5) search implementations
- `backlinks.ts` — Inter-document link graph
- `lifecycle.ts` — Port/PID file management, project root detection

### Data flow

1. Python scripts clone docs from GitHub, strip frontmatter/MDX, output clean markdown
2. Search service indexes the markdown into SQLite: chunks table (with embeddings in vec0 virtual table) + FTS5 full-text index
3. The `hass-docs-search` subagent queries the HTTP API and reads files as needed

## Commands

### Search service

```bash
# Install dependencies (first time)
pnpm --dir .claude/skills/hass-dev-docs/service install

# Start service (dynamic port written to .hass-docs-port)
pnpm --dir .claude/skills/hass-dev-docs/service start

# Stop service
kill $(cat .hass-docs-pid)
```

### Update docs

```bash
# Developer docs
python .claude/skills/hass-dev-docs/scripts/update-docs.py docs/hass-developer

# User docs
python .claude/skills/hass-dev-docs/scripts/update-user-docs.py docs/hass-user
```

### Search API (when service is running)

```bash
PORT=$(cat .hass-docs-port)

# Semantic search (supports ?doc_set=hass-user|hass-developer)
curl "http://localhost:$PORT/search?q=config+flow&limit=5"

# Keyword search
curl "http://localhost:$PORT/search/keyword?q=ConfigEntry&limit=5"

# Service stats
curl "http://localhost:$PORT/stats"
```

## Key constraints

- The search service must run under **Node.js** (not Bun) — Transformers.js ONNX runtime has issues with Bun
- sqlite-vec's vec0 virtual table does **not** support bound `?` parameters for primary key columns when using better-sqlite3. Use template literals for PKs, bound params for embeddings only (see `indexer.ts`)
- Package manager is **pnpm**
- The `docs/` directories are auto-generated — edit the update scripts, not the docs directly. The weekly workflow `.github/workflows/update-claude-code.yml` regenerates them and bumps `DOCS_STAMP` in `addon/Dockerfile`
- `resources/` is gitignored — it holds cloned upstream repos that can be re-downloaded

## Copilot instructions (from upstream HA docs repo)

When editing content in `resources/home-assistant-io/`, follow the HA writing style:
- American English, Microsoft Style Guide, sentence-style capitalization
- Use "Home Assistant" in full (never "HA" or "HASS")
- Use `**bold**` only for UI strings, `_italics_` for emphasis
- YAML: 2-space indent, `true`/`false` booleans, double-quoted strings, block-style sequences
- Prefer lists over tables (mobile readability)
