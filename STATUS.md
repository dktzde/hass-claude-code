# Status and next steps

Handover file for the maintainer and for Claude Code sessions working on this repository. **Read this first, and update it after every step** (state, decisions, next steps), so the next session can continue without the chat history.

Last updated: 2026-10-09 (evening)

## Current state

- **Add-on version on `main`: 0.3.4** (automated releases 0.3.2–0.3.4: Claude Code, npm lockfile within the majors, docs). The maintainer's device (an old x86 laptop, `amd64`) was checked on 0.3.2 on 2026-10-08 18:04: `managed-settings.json` holds only `permissions`, the generated `CLAUDE.md` names `/core/logs`, `/root/.claude` points to `/data/.claude`, `gh` is logged in, python3, PyYAML, mosquitto and the `MQTT_*` variables, MCP server and docs search work.
- **Merged since 0.3.0:**
  - 0.3.0 (#9): semantic doc search removed (about 350 MB smaller image), typo-tolerant FTS5 keyword search in `src/search.ts`, stored values of removed options cleaned up on start (`removed_options` in `init-claude`; **add future removed options there**).
  - 0.3.1 (#10): yolo mode no longer writes the dead key `"permissions.defaultMode"` (not moved into `permissions` on purpose: a managed default mode would override the users' own mode); the generated `CLAUDE.md` points to `/core/logs` instead of `/core/api/error_log`.
  - #11 and #12 (docs only, no new version): README "Quick guide", `examples/chat-log-hook/` (one file per tmux window), workflow issues in English.
- Upstream dkmaker/hass-claude-code#10 (semantic search analysis) was closed as "not planned" on 2026-10-09: Claude sends precise English HA queries, keyword search is enough.
- **Contents of the image:**
  - Claude Code 2.1.295 (pinned)
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
- **Last green runs:** the automated releases 0.3.3 (run 37906784853) and 0.3.4 (run 37977993166) on `main`.

## Next step: plan B = version 0.4.0 (scheduled: Saturday 2026-10-10, evening)

The maintainer decided to do the base image switch (#5) and **all** npm major updates (#6) **in one PR**, so the device needs to be tested only once, with extended tests that stay in the workflow permanently. The alternative (two separate steps) was rejected.

**Schedule (agreed 2026-10-09):**

- **Saturday 2026-10-10, evening:** Claude works through steps 1–5 below in one go, without stopping for each step:
  - One branch (for example `feat/alpine-3.24-npm-majors`), **two commits**: first the base image (#5), then the npm majors and the tests (#6). Start the Action on the branch by hand after each commit, so a failing build points to one of them, and fix until both runs are green.
  - Things that cannot be updated cleanly (for example TypeScript 7) stay as they are and are listed for the maintainer, instead of being forced.
  - Then the PR, merge, the Action run on `main` that releases 0.4.0. Show the maintainer the diff before merging, if they are still there.
- **Sunday 2026-10-11, morning:** the maintainer updates to 0.4.0 in Home Assistant ("backup before update") and tests on the device (step 5). If something breaks, revert only the commit at fault.
- The weekly Action runs on Saturday 05:47 UTC and may release 0.3.5 before; start the branch from the current `main` and pull again before merging.

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
- **Language:** code, README, changelog, commits and the issues created by the workflow in English (issues since 2026-10-09). Replies to the maintainer in German, in plain language.
- **Workflow:**
  - One PR per topic.
  - Before merging, run the Action by hand on the PR branch (Run workflow → choose the branch). That run never pushes.
  - After merging, run it on `main` once, so the release has the current package list.
- **Report scripts** (`.github/scripts/`) exit with an error instead of printing nothing when a data source is down, so an outage never closes an issue.
- **Issue titles** are the key the workflow finds its issues by. When a title changes, add the old one to `retitle_issue` (or the failure job's lookup), so the open issue is renamed instead of a second one opened. The German titles there can go once no open issue carries them.

## Key files

- `addon/Dockerfile`, `addon/config.yaml`, `addon/build.yaml`, `addon/packages.txt`, `addon/CHANGELOG.md`, `addon/translations/`
- `addon/rootfs/etc/s6-overlay/s6-rc.d/init-claude/run`: environment, persistence, MQTT, managed CLAUDE.md
- `addon/mcp-server/`: MCP server (TypeScript), lockfile, `pnpm-workspace.yaml` (`allowBuilds`)
- `.github/workflows/update-claude-code.yml`: weekly update, issues, failure issue
- `.github/scripts/`: `mcp-smoke-test.sh`, `sync-issue.sh`, `support-lib.sh`, `base-image-report.sh`, `npm-report.sh`
- `.claude/skills/update-claude/SKILL.md`: manual Claude Code update
- `examples/chat-log-hook/`: optional Stop hook for users (daily chat log), not part of the image
