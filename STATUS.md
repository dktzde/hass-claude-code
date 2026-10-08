# Status and next steps

Handover file for the maintainer and for Claude Code sessions working on this repository. **Read this first, and update it after every step** (state, decisions, next steps), so the next session can continue without the chat history.

Last updated: 2026-10-08

## Current state

- **Add-on version on `main`: 0.3.0** (dktzde/hass-claude-code#9, merged 2026-10-07). It runs on the maintainer's device (an old x86 laptop, `amd64`) since 2026-10-07 18:25:
  - Removes the semantic doc search. It never worked, see the changelog. The image gets about 350 MB smaller, and `search_docs` becomes keyword-only (SQLite FTS5) with no embedding or vector dependencies.
  - Makes the keyword search robust, in `src/search.ts`. It tries the query as FTS5 syntax first, then all words, then all words with typos corrected, then any word. Typos are corrected against the FTS5 vocabulary (`chunks_vocab`, an `fts5vocab` table) with an edit distance of 1–2, preferring the same first letter and then the more common word. The tool output then carries a second text item with the corrected query.
  - Removes stored values of removed options (`api_key`, `enable_embeddings`) from the add-on configuration on start through the Supervisor API (`init-claude`). **When an option is removed in future, add it to `removed_options` there.**
  - Checked on the device on 2026-10-08: the options only hold `model`, `yolo_mode` and `additional_packages`; tools, `gh` login, MCP server and keyword docs search work.
- **In review: 0.3.1** (dktzde/hass-claude-code#10, branch `fix/managed-settings-and-log-hint`), two bug fixes, see the changelog:
  - Yolo mode no longer writes the dead key `"permissions.defaultMode"` (with a dot, never read by Claude Code). Not moved into `permissions` on purpose: a managed default mode would override the mode users choose themselves.
  - The generated `CLAUDE.md` points to the Supervisor endpoint `/core/logs` instead of `/core/api/error_log` (404 on Home Assistant OS).
  - Before merging: test run of the Action on the branch. After merging: update in Home Assistant, then check that `/etc/claude-code/managed-settings.json` has only the `permissions` key.
- **Contents of the image:**
  - Claude Code 2.1.292 (pinned)
  - Python 3.12 with PyYAML, `mosquitto_pub` and `mosquitto_sub`, the GitHub CLI `gh`
  - Node.js 24, git, ripgrep, tmux, ttyd
  - Base image `ghcr.io/hassio-addons/base:20.0.1` (Alpine 3.23)
- **Weekly GitHub Action** (`.github/workflows/update-claude-code.yml`, Saturday 05:47 UTC, also started by hand):
  - Updates Claude Code, the Alpine packages (`addon/packages.txt` and `PACKAGES_STAMP`), the npm lockfile (within the majors) and the docs (`DOCS_STAMP`).
  - Test-builds the image, checks the tools and smoke-tests the MCP server, then releases any change as one add-on version.
  - Manual runs on other branches than `main` are test runs: they build and check, but never push.
  - It opens or updates issues for what stays manual: fork commits, base image and Alpine support end, npm majors, and failed runs.
- **Open issues:**
  - dktzde/hass-claude-code#5: base image 21.0.8 (Alpine 3.24) is available. The community repository of Alpine 3.23 (ttyd, ripgrep, github-cli) has had no updates since 2026-06-09; main gets updates until 2027-11-01.
  - dktzde/hass-claude-code#6: new npm major versions, see next steps.
- **Last green runs:** run 37628361900 (test run of 0.2.0 on the branch) and the release of 0.2.1 on `main`.

## Next step: plan B (agreed, start "in some time")

The maintainer decided to do the base image switch and **all** npm major updates **in one PR**, with extended tests that stay in the workflow permanently. The alternative (two separate steps) was rejected.

### 1. Find out what Alpine 3.24 brings

Start the Action by hand on the new branch once the base image is switched, or run:

```bash
docker run --rm --entrypoint sh ghcr.io/hassio-addons/base:21.0.8 -c \
  'apk add --no-cache nodejs python3 >/dev/null && node -v && python3 -V && cat /etc/alpine-release'
```

The Node.js major decides the `@types/node` range, and a Python change is worth a changelog line.

### 2. Base image

- `addon/Dockerfile`: `ARG BUILD_FROM=ghcr.io/hassio-addons/base:21.0.8`. The current Supervisor builder reads only the Dockerfile.
- `addon/build.yaml`: same version for both architectures. Older Supervisors still pass `build_from` from it, and without the file they would use a different default image.
- `addon/Dockerfile`, builder stage: `FROM alpine:3.24 AS mcp-builder`. It must match the Alpine version of the base image, so that better-sqlite3 is compiled for the same Node.js.
- Check that all `apk add` packages exist in 3.24 under the same names. The image check step fails otherwise.

### 3. npm major updates (`addon/mcp-server/package.json`)

| Package | Now | Target | Notes |
|---|---|---|---|
| `better-sqlite3` | ^11 | ^13 | Needs Node >= 22. Uses `node-addon-api` (ABI-stable), which removes the risk of a Node major change. `pnpm-workspace.yaml` `allowBuilds` keeps `better-sqlite3: true`. |
| `zod` | ^3.23 | ^4 | **Code change needed:** `src/index.ts`, `call_service` uses `z.record(z.unknown())`; zod 4 needs `z.record(z.string(), z.unknown())`. `@modelcontextprotocol/sdk` 1.32 accepts `zod ^3.25 \|\| ^4`. Check all tool schemas still produce the same JSON schema in `tools/list`. |
| `glob` | ^11 | ^13 | Used once in `src/indexer.ts` (`glob('**/*.md', ...)`). The named export `glob` still exists; verify the options. |
| `typescript` (dev) | ^5 | **^6** | TypeScript 7 is the new native compiler with platform binaries. Take 6 as the safe step; 7 is optional. |
| `@types/node` (dev) | ^22 | Node major of Alpine 3.24 | Match the runtime, not the latest version. |
| `@types/better-sqlite3` (dev) | ^7 | ^9 | Must compile against better-sqlite3 13. |

Regenerate the lockfile the same way the workflow does: in the builder's Alpine image with pnpm 11, `pnpm install --lockfile-only`.

### 4. Extended tests (stay in the workflow)

Extend `.github/scripts/mcp-smoke-test.sh` or add a script next to it:

- **`call_service` input:**
  - Check that `tools/list` describes `call_service.data` as an object.
  - Call `call_service` with valid input (`{"domain":"light","service":"turn_on","data":{"entity_id":"light.smoke_test"}}`). There is no Home Assistant in CI, so the call must fail with a connection error, **not** with an input validation error.
  - Call it with invalid input (no `domain`), which must give a validation error. Together they prove that zod validates and accepts correctly.
- **Docs search:** already covered. The smoke test also runs a dotted query (`light.turn_on`) and a typo (`automaton trigger`, which must be corrected to `automation trigger`).

### 5. Release

- Version **0.4.0**: new minor version because of the Alpine switch and the dependency majors. Changelog with the new Python and Node.js versions.
- Test run of the Action on the branch, then merge, then run the Action on `main`, then update in Home Assistant with "backup before update".
- Manual check on the device:
  - The add-on starts.
  - Claude can switch a light on and off (this exercises `call_service` with zod 4).
  - `search_docs` works.
- Issues #5 and #6 close themselves on the next run once everything is current.

## Known issues and backlog

- **`aarch64` (Raspberry Pi) is never test-built.** CI builds `amd64` only. A QEMU arm64 build would work but is slow. The README says it is untested.
- `addon/README.md` and `addon/DOCS.md` do not exist, so the add-on overview and the Documentation tab in Home Assistant are empty. `url` in `config.yaml` links to this repository instead.
- The option `additional_packages` installs packages on every start (needs internet, start fails if a package is missing).
- **Docs search** is SQLite FTS5 with the fallbacks and typo correction above. Alternatives such as MiniSearch, Fuse.js or Typesense were considered; FTS5 plus its own vocabulary needs no new dependency and keeps the index built at image build time.
- The semantic doc search was **removed** in 0.3.0 at the maintainer's request (Claude does not need it; it never worked because the docs were never indexed with embeddings). Do not bring back Transformers.js, ONNX Runtime or sqlite-vec without a new decision.
- Prebuilt images (building in CI and pulling instead of building on the device) were considered and **rejected** for now. Building on the device works, and the stamps solve the layer cache problem.

## Decisions and conventions

- **Layer cache:** the Supervisor builds with the Docker layer cache. Everything that must update is pinned in `addon/Dockerfile`:
  - `CLAUDE_CODE_VERSION`
  - `PACKAGES_STAMP`, a hash of `addon/packages.txt`
  - `DOCS_STAMP`, the git tree hash of `docs/`
  - plus the npm lockfile

  Never edit the stamps or `addon/packages.txt` by hand; the workflow maintains them.
- **Login** only through Claude Code (the `api_key` option was removed in 0.2.0). The login lives in `/data`.
- **CLAUDE.md in the add-on:** `init-claude` writes `/etc/claude-code/CLAUDE.md` on every start; Claude Code loads it as managed memory. `/homeassistant/CLAUDE.md` belongs to the user: it is created only when missing and **never overwritten**.
- **MQTT:** `services: mqtt:want`. With the Mosquitto broker add-on, `init-claude` exports `MQTT_HOST`, `MQTT_PORT`, `MQTT_USERNAME` and `MQTT_PASSWORD`.
- **Versioning:** the workflow bumps the patch level (0.2.1, 0.2.2, …). Bigger changes get a new minor version by hand.
- **Changelog:** automated entries start with "**Automated update** by the GitHub Action …", without "not made by hand".
- **Language:** code, README, changelog and commits in English. Issues created by the workflow, and replies to the maintainer, in German, in plain language.
- **Workflow:**
  - One PR per topic.
  - Before merging, run the Action by hand on the PR branch (Run workflow → choose the branch). That run never pushes.
  - After merging, run it on `main` once, so the release has the current package list.
- **Report scripts** (`.github/scripts/`) exit with an error instead of printing nothing when a data source is down, so an outage never closes an issue.

## Key files

- `addon/Dockerfile`, `addon/config.yaml`, `addon/build.yaml`, `addon/packages.txt`, `addon/CHANGELOG.md`, `addon/translations/`
- `addon/rootfs/etc/s6-overlay/s6-rc.d/init-claude/run`: environment, persistence, MQTT, managed CLAUDE.md
- `addon/mcp-server/`: MCP server (TypeScript), lockfile, `pnpm-workspace.yaml` (`allowBuilds`)
- `.github/workflows/update-claude-code.yml`: weekly update, issues, failure issue
- `.github/scripts/`: `mcp-smoke-test.sh`, `sync-issue.sh`, `support-lib.sh`, `base-image-report.sh`, `npm-report.sh`
- `.claude/skills/update-claude/SKILL.md`: manual Claude Code update
