# Status and next steps

Handover file for the maintainer and for Claude Code sessions working on this repository. **Read this first, and update it after every step** (state, decisions, next steps), so the next session can continue without the chat history.

Last updated: 2026-10-25 (0.7.2: s6 user bundle in user-bundles.d)

## Current state

- **0.7.2 (branch `s6-user-bundles`): start-up warning of s6-overlay fixed.** s6-overlay 3.2.3.2 (base image) warns when `/etc/s6-overlay/s6-rc.d/user` exists and reads the `user` bundle from `/etc/s6-overlay/user-bundles.d` instead (see `rc.init`). The four `contents.d` entries moved there; the base image already ships `user-bundles.d/user/type`, so the add-on only adds `contents.d`. No new service directory under `s6-rc.d` may be called `user` or `user2`. New services go into `addon/rootfs/etc/s6-overlay/user-bundles.d/user/contents.d/`.
- **0.7.1 on the device since 2026-10-25 ≈ 07:45 (local time), checked the same day:** add-on started, version 0.7.1, Alpine 3.24.3, Python 3.14.8, Node.js 24.22.1, Claude Code 2.1.310, `gh` logged in. MCP: `search_docs`, `list_areas` (15 areas), `search_devices` and `call_service` (`logbook.log`) work. The log has no errors and no bashio warning; only the known s6-overlay note "defining user bundles in /etc/s6-overlay/s6-rc.d is deprecated" (harmless). #18 closed.
- **0.7.0 (branch `base-image-21.0.9`, Refs #18): base image 21.0.9** (Alpine 3.24.3, musl 1.2.6-r3; bashio, s6-overlay and tempio unchanged, so `addon/rootfs` needs no change). Only `ARG BUILD_FROM` in `addon/Dockerfile` and `addon/build.yaml` changed; the builder stays `alpine:3.24`. The next automated release becomes 0.7.1 and refreshes `addon/packages.txt`.
- **0.6.0 (merged 2026-10-24): several sessions from a phone.** New option `mobile_tabs` (default `false`, maintainer's request). With it on, `ttyd/run` starts tmux with `-f /etc/tmux-mobile.conf` (`addon/rootfs/etc/tmux-mobile.conf`): mouse on, `base-index 1`, a status bar with one tappable range per window (`range=window|N`) and a `+` button (`range=user|new`, needs tmux 3.4 or newer; the image has 3.7). `MouseDown1Status` starts `claude-entrypoint.sh` in a new window for `+` and selects the window otherwise. Leaving a window with `/exit` closes it. Tested here only with simulated taps in a pty (tmux 3.4); **not tested on the phone yet**. Known limits: tmux owns the mouse then (swipe scrolls the history, selection goes through tmux), and `login-link` reads only the active window of the session.
- **0.5.1 (#20, merged 2026-10-24):** the login link notification of 0.5.0 is now behind the option `mobile_login` (default `false`, maintainer's request). With it off, `login-link/run` only does `exec sleep infinity` (a longrun that exits is restarted by s6). The maintainer confirmed on the phone that 0.5.0 works.
- **0.5.0 (#19, merged 2026-10-24): login from a phone.** The maintainer could not copy the login URL in the web terminal on a phone: Claude Code captures the mouse (it prints "Hold Shift while selecting…"), and the URL is wrapped over several lines. Two fixes:
  - New service `login-link` (`addon/rootfs/etc/s6-overlay/s6-rc.d/login-link/run`): every 3 s it reads the tmux pane `claude`, joins the wrapped `oauth/authorize` URL and sends it as the persistent notification `claude_code_login` (Core API through the Supervisor proxy); it dismisses the notification once the URL is gone. Works on the maintainer's phone.
  - New option `disable_mouse` (default `false`): `init-claude` writes `CLAUDE_CODE_DISABLE_MOUSE=1`, so the terminal does its own selection.
  - If a Claude Code update changes the login screen and the URL is no longer found, adjust `find_login_url`.
  - Versions 0.5.0, 0.5.1 and 0.6.0 and their changelog entries were written by hand.
- **0.4.2 in review: dktzde/hass-claude-code#16** (branch `fix/mcp-websocket-registry`). The MCP tools `list_areas`, `search_devices` and `get_config_entries` always returned `[]`: they sent websocket commands as a REST `POST` to `/core/api` (405, error hidden). They now use `ws://supervisor/core/websocket`, errors are reported, and the smoke test checks it. Tested on the device over stdio (15 areas, 77 devices, 37 config entries).
- **0.4.1 on the device since 2026-10-09 22:23 (local time)**, checked 2026-10-10: the add-on starts without errors, Alpine 3.24.2, Python 3.14.8, Node.js 24.18, `gh` logged in, MQTT and the Core API work, `search_docs` and `get_entity_state` work. Not checked yet: `call_service` (switching a light).
- **Add-on version on `main`: 0.4.1**, released 2026-10-09 20:12 UTC (run 37985313879).
  - 0.4.0 is plan B, dktzde/hass-claude-code#14, merged with a merge commit: base image switch and all npm major updates. It fixes dktzde/hass-claude-code#5 and dktzde/hass-claude-code#6; the merge closed both, and the report job of the release run found nothing left to report. The maintainer had planned it for Saturday evening (branch `docs/status-plan-0.4.0`), then moved it to Friday 2026-10-09 evening: "work through it on your own, so I can test a finished release tomorrow". [`MAINTENANCE.md`](MAINTENANCE.md) holds the checklists and every pitfall of this update.
  - 0.4.1 is the automated release on top: the Alpine 3.24 package list in `addon/packages.txt` and Claude Code 2.1.296.
  - Commits of #14, one per topic as the plan asked (a test run after each; each can be reverted alone with `git revert <commit>`):
    1. `e28d082` `ci:` test runs on branches no longer change issues; the failure issue is for `main` only; the report job runs after the update job on the branch head.
    2. `058f07d` `feat(addon):` base image `ghcr.io/hassio-addons/base` 21.0.8 (Alpine 3.24): **Python 3.14** (was 3.12), Node.js stays 24, builder `alpine:3.24`; `ttyd/run` uses `bashio::app.ingress_port` (bashio 0.18 renamed `bashio::addon.*`). Version 0.4.0. Test run 37984697694 built this alone (with better-sqlite3 11).
    3. `dc94830` `feat(mcp-server):` better-sqlite3 13 (prebuilt musl binaries, so the builder drops `build-base` and `python3`), zod 4, glob 13, **TypeScript 7**, `@types/better-sqlite3` 9, `@types/node` 24; smoke test for `call_service` (valid and invalid input); npm report compares `@types/node` with the Node.js of the image. Test run 37985066042.
    4. `47d9636` `docs:` `MAINTENANCE.md`, this file, README, CLAUDE.md, links from the issue texts.
  - Before these, the same changes were pushed as one combined commit (`20df72f`, test run 37984205004) and reverted (`23737da`), because the branch could not be rewritten.
  - **TypeScript 7 instead of 6:** the plan said to leave TypeScript 7 for the maintainer if it does not update cleanly. It did: it compiles without changes (besides `"types": ["node"]`, needed from TypeScript 6 on anyway), emits the same JavaScript as TypeScript 5, and builds in Alpine. Only 7 closes #6. If it causes trouble, set `typescript` to `^6.0.0` and regenerate the lockfile.
  - zod 4 changes the JSON schema in `tools/list` slightly (no `additionalProperties: false`, `propertyNames` on `data`); behavior is the same, checked against the old build.
- **Before 0.4.0: 0.3.4** (automated releases 0.3.2–0.3.4: Claude Code, npm lockfile within the majors, docs). The maintainer's device (an old x86 laptop, `amd64`) was checked on 0.3.2 on 2026-10-08 18:04: `managed-settings.json` holds only `permissions`, the generated `CLAUDE.md` names `/core/logs`, `/root/.claude` points to `/data/.claude`, `gh` is logged in, python3, PyYAML, mosquitto and the `MQTT_*` variables, MCP server and docs search work.
- **Merged since 0.3.0:**
  - 0.3.0 (#9): semantic doc search removed (about 350 MB smaller image), typo-tolerant FTS5 keyword search in `src/search.ts`, stored values of removed options cleaned up on start (`removed_options` in `init-claude`; **add future removed options there**).
  - 0.3.1 (#10): yolo mode no longer writes the dead key `"permissions.defaultMode"` (not moved into `permissions` on purpose: a managed default mode would override the users' own mode); the generated `CLAUDE.md` points to `/core/logs` instead of `/core/api/error_log`.
  - #11 and #12 (docs only, no new version): README "Quick guide", `examples/chat-log-hook/` (one file per tmux window), workflow issues in English.
- Upstream dkmaker/hass-claude-code#10 (semantic search analysis) was closed as "not planned" on 2026-10-09: Claude sends precise English HA queries, keyword search is enough.
- **Contents of the image (0.4.1):**
  - Claude Code 2.1.296 (pinned)
  - Python 3.14 with PyYAML, `mosquitto_pub` and `mosquitto_sub`, the GitHub CLI `gh` 2.97
  - Node.js 24, git, ripgrep, tmux, ttyd
  - Base image `ghcr.io/hassio-addons/base:21.0.9` (Alpine 3.24, since 0.7.0)
- **Weekly GitHub Action** (`.github/workflows/update-claude-code.yml`, Saturday 05:47 UTC, also started by hand):
  - Updates Claude Code, the Alpine packages (`addon/packages.txt` and `PACKAGES_STAMP`), the npm lockfile (within the majors) and the docs (`DOCS_STAMP`).
  - Test-builds the image, checks the tools and smoke-tests the MCP server, then releases any change as one add-on version.
  - Manual runs on other branches than `main` are test runs: they build and check, but never push and never change issues.
  - Then reports what stays manual as issues: fork commits, base image and Alpine support end, npm majors; plus one issue for failed runs on `main`.

## Next steps

0. Test 0.6.0 on the phone: turn on `mobile_tabs`, restart, tap `+`, switch tabs; also `mobile_login`. Run the Action on `main` once (nothing was test-run on a branch for 0.5.x and 0.6.0).
1. #16: test run of the Action on the branch, merge, run the Action on `main`, update and check `list_areas` on the device.
2. 0.4.1 on the device (installed, see above): still open is only that Claude can switch a light on and off (this exercises `call_service` with zod 4). Checked 2026-10-10: the add-on starts, the log shows no `bashio::addon` deprecation warning, `search_docs` works, `python3 --version` says 3.14.
   - If something breaks, revert only the commit at fault (`058f07d` base image or `dc94830` npm majors, see above) on a branch, test-run, merge and release again.
3. The branch `docs/status-plan-0.4.0` is superseded by this file and can be deleted.
4. Expect #5 to reopen (as a new issue) around mid-November 2026 as an advance notice: 30 days before the estimated end of the Alpine 3.24 community repository (release 2026-06-09 + 6 months), until Alpine 3.25 and a new base image are out. That is by design, see `MAINTENANCE.md`.

## Known issues and backlog

- **`aarch64` (Raspberry Pi) is never test-built.** CI builds `amd64` only. A QEMU arm64 build would work but is slow. The README says it is untested.
- `addon/README.md` and `addon/DOCS.md` do not exist, so the add-on overview and the Documentation tab in Home Assistant are empty. `url` in `config.yaml` links to this repository instead.
- The option `additional_packages` installs packages on every start (needs internet, start fails if a package is missing).
- **Docs search** is SQLite FTS5 with the fallbacks and typo correction above. Alternatives such as MiniSearch, Fuse.js or Typesense were considered; FTS5 plus its own vocabulary needs no new dependency and keeps the index built at image build time.
- The semantic doc search was **removed** in 0.3.0 at the maintainer's request (Claude does not need it; it never worked because the docs were never indexed with embeddings). Do not bring back Transformers.js, ONNX Runtime or sqlite-vec without a new decision.
- Prebuilt images (building in CI and pulling instead of building on the device) were considered and **rejected** for now. Building on the device works, and the stamps solve the layer cache problem.
- better-sqlite3 13 adds about 15 MB to the image (SQLite sources and prebuilt binaries for all platforms). The builder could delete `deps/`, `src/` and the binaries of other platforms after `pnpm prune --prod`; not done, to keep the build simple.
- Claude Code cloud sessions cannot build the image (image layers from `ghcr.io`, Docker Hub and the Alpine CDN are blocked or rate-limited there). Build with the test run of the Action; `MAINTENANCE.md` shows how to test the MCP server locally with Node.js.

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
- **Changelog:** automated entries start with "**Automated update** by the GitHub Action …", without "not made by hand". Every version of this fork (0.1.12 and later) has its date as `<sub>YYYY-MM-DD</sub>` under the heading (the workflow writes it in UTC); 0.1.0–0.1.11 are the original add-on by dkmaker, marked with a note above 0.1.11.
- **Language:** code, README, changelog, commits and the issues created by the workflow in English (issues since 2026-10-09). Replies to the maintainer in German, in plain language.
- **Workflow:**
  - One PR per topic.
  - Before merging, run the Action by hand on the PR branch (Run workflow → choose the branch). That run never pushes and never changes issues; its step summary shows what it would release and which issues it would open or close.
  - After merging, run it on `main` once, so the release has the current package list.
- **Report scripts** (`.github/scripts/`) exit with an error instead of printing nothing when a data source is down, so an outage never closes an issue.
- **Issue titles** are the key the workflow finds its issues by. When a title changes, add the old one to `retitle_issue` (or the failure job's lookup), so the open issue is renamed instead of a second one opened. The German titles there can go once no open issue carries them.

## Key files

- `MAINTENANCE.md`: checklists and pitfalls for base image and npm major updates
- `addon/Dockerfile`, `addon/config.yaml`, `addon/build.yaml`, `addon/packages.txt`, `addon/CHANGELOG.md`, `addon/translations/`
- `addon/rootfs/etc/s6-overlay/s6-rc.d/init-claude/run`: environment, persistence, MQTT, managed CLAUDE.md
- `addon/mcp-server/`: MCP server (TypeScript), lockfile, `pnpm-workspace.yaml` (`allowBuilds`)
- `.github/workflows/update-claude-code.yml`: weekly update, issues, failure issue
- `.github/scripts/`: `mcp-smoke-test.sh`, `sync-issue.sh`, `support-lib.sh`, `base-image-report.sh`, `npm-report.sh`
- `.claude/skills/update-claude/SKILL.md`: manual Claude Code update
- `examples/chat-log-hook/`: optional Stop hook for users (daily chat log), not part of the image
