# Maintenance

Checklists and pitfalls for the updates the weekly Action only reports as issues: a new base image (often a new Alpine version) and new major versions of the MCP server's npm dependencies. The routine updates (Claude Code, Alpine packages, npm within the majors, docs) run on their own, see "Updates" in the [README](README.md).

The last two sections keep the decisions and conventions of this repository and its known issues (moved here from the former `STATUS.md`).

Each update section ends with what went wrong or nearly went wrong last time, so the next update does not trip over it again. Add to it after every such update.

## How a manual update is released

1. Work on a branch. Change the files below, set a new minor version in `addon/config.yaml` (for example 0.4.0) and write the `addon/CHANGELOG.md` entry by hand.
2. One commit per topic, for example the base image first and the npm majors second, and a test run after each: run the Action "Update add-on" on the branch (Actions → Update add-on → Run workflow → choose the branch). A failing run then points to one commit, and a commit that breaks on a device can be reverted alone. Merge the PR with a merge commit, not squashed, so the commits stay separate on `main`.
3. A run on any branch but `main` is a test run: it builds and checks the image, but never pushes and never changes issues. The step summary lists what it would have released and which issues it would have opened or closed.
4. Merge, then run the Action on `main` once. Home Assistant offers the new minor version (0.4.0) as soon as the merge is on `main`; the run adds a patch version on top (0.4.1) a few minutes later, so update after that run. Never edit `addon/packages.txt`, `PACKAGES_STAMP` or `DOCS_STAMP` by hand: this run refreshes them, for example with the package list of the new Alpine version.
5. The report job runs after that release and checks out the new `main`, so the base image and npm issues close in the same run. Write "Refs #5" in the PR, not "Fixes #5": with "Fixes", GitHub closes the issue at the merge already, before the report job has checked anything, and if something is still left, the next run opens a new issue instead of updating the old one (0.4.0 did this; nothing was left, so it did no harm).
6. Update in Home Assistant with "backup before update", then check on the device: the add-on starts, Claude can switch a light on and off (`call_service`), `search_docs` finds something.

Plan the commit split before the first push. In Claude Code cloud sessions, rewriting a pushed branch (reset, force push) is blocked; for 0.4.0 the combined first commit was undone with `git revert` and the topics were committed again one by one.

## Base image and Alpine version

Files:

- `addon/Dockerfile`: `ARG BUILD_FROM=ghcr.io/hassio-addons/base:<version>`, a multi-arch image, so one line serves both architectures. There is no `addon/build.yaml` any more (removed 2026-11-23): the Supervisor builds without it since 2026.04.0 (home-assistant/supervisor#6694, see "Previously, … build.yaml" in the developer docs under apps/configuration) and warned on every update that it is deprecated. A Supervisor older than that would fall back to its own default base image, but the Supervisor updates itself.
- `addon/Dockerfile`, builder stage: `FROM alpine:<X.Y> AS mcp-builder`, the same Alpine version as the base image.

Checks:

- **Same Alpine in builder and base image.** The builder runs `pnpm install` and copies `node_modules` into the add-on. pnpm picks platform packages (and better-sqlite3 its prebuilt binary) for the builder's libc (musl) and Node.js, so both stages must match. better-sqlite3 13 uses N-API binaries that work across Node.js majors, but musl versus glibc still matters.
- **Do all packages exist under the same names?** `apk add` in the Dockerfile fails otherwise, and so does the test run. Without Docker, read the APKBUILD files on the `<X.Y>-stable` branch of the aports mirror: `https://raw.githubusercontent.com/alpinelinux/aports/3.24-stable/<main|community>/<package>/APKBUILD` (`pkgver`, `subpackages`). `mosquitto-clients` is a subpackage of `mosquitto`, `libgcc` and `libstdc++` are subpackages of `gcc`.
- **Python and Node.js versions.** Read `pkgver` of `main/python3` and `main/nodejs` there. A new Python version gets a changelog line (users may run their own scripts). A new Node.js major means `@types/node` must follow, see below.
- **Base image release notes.** Look at the changes of `hassio-addons/app-base` between the two tags (bashio, s6-overlay, tempio versions in `base/Dockerfile`). Then search `addon/rootfs` for every `bashio::` function that changed.
- **Support dates in the issue.** The base image issue also opens without a new base image, 2 days before the community repository of the installed Alpine version stops getting updates (30 days until 2026-11-22: the issue stayed open for weeks with nothing to do). Until the next Alpine version is out, that date is estimated as release date + 6 months.

Pitfalls of the switch to Alpine 3.24 (base image 21.0.8, add-on 0.4.0):

- **bashio 0.18 renamed `bashio::addon.*` to `bashio::app.*`.** The old names still work but log a deprecation warning. `ttyd/run` used `bashio::addon.ingress_port`.
- **Python jumped from 3.12 to 3.14.** Alpine 3.23 kept 3.12; 3.24 skipped 3.13.
- **Node.js stayed at 24** (`nodejs` in main). Alpine 3.24 also has `nodejs-current` (26) in community; the add-on uses `nodejs`.
- **`addon/packages.txt` is stale right after the switch.** It still lists the old Alpine until the first run on `main` refreshes it. Until 0.4.0 the report job read it before that refresh, so the base image issue stayed open (with the old Alpine shown) until the following week. The report job now runs after the update job and checks out the branch head.
- **Test runs on branches changed issues.** Until 0.4.0 a test run on a branch would have closed the issues for changes that were not merged yet. `sync-issue.sh` now only writes to the step summary on any ref but `main`, and the failure issue is only for `main`.

## npm major updates

Files: `addon/mcp-server/package.json`, `pnpm-lock.yaml`, maybe `tsconfig.json` and `src/`.

Steps:

1. Raise the range in `package.json`.
2. Regenerate the lockfile **from scratch**, like the workflow does:

   ```bash
   cd addon/mcp-server
   rm -rf node_modules pnpm-lock.yaml
   npx -y pnpm@11 install --lockfile-only
   ```

   With `node_modules` present, pnpm reuses `node_modules/.pnpm/lock.yaml` and keeps old transitive versions. The weekly run regenerates without it, and the difference turns into an extra npm update after the merge. The lockfile is the same on every platform, so this can run outside Alpine.
3. Install, build, index and compare the MCP server before and after (see "Test without Docker").

Rules:

- **`@types/node` follows the Node.js major of the image**, not the latest `@types/node`: the `nodejs` package in `addon/packages.txt`. `npm-report.sh` knows this and does not report a newer `@types/node` major while the image runs an older Node.js.
- **Check peer dependencies before a major**, for example `@modelcontextprotocol/sdk` declares `zod: ^3.25 || ^4.0`.
- **pnpm 11** reads the build-script allowlist only from `pnpm-workspace.yaml` (`allowBuilds`). A dependency that wants a build script and is not listed makes the install fail with `ERR_PNPM_IGNORED_BUILDS`.

Pitfalls of the update in 0.4.0:

- **zod 3 → 4:** `z.record(valueSchema)` must become `z.record(z.string(), valueSchema)`; `tsc` reports it as `TS2554: Expected 2-3 arguments`. The JSON schema in `tools/list` changes slightly: the tool inputs lose `"additionalProperties": false` and records get `"propertyNames": {"type": "string"}`. Behavior is the same: unknown arguments are still stripped, not rejected. zod's error texts changed (`Invalid input: expected string, received undefined`), so tests match the SDK's `Input validation error`, never zod's wording.
- **TypeScript 5 → 7:**
  - Since TypeScript 6, `types` defaults to `[]`, so `@types/node` is no longer loaded on its own. It only came in through `@types/better-sqlite3`; `tsconfig.json` now lists `"types": ["node"]`.
  - TypeScript 7 is the native compiler. The `typescript` package pulls one binary per platform (`@typescript/typescript-linux-x64`, `-linux-arm64`, …, about 28 MB each) as optional dependencies. It works on Alpine (static binary) and is only needed at build time; `pnpm prune --prod` removes it.
  - For this code TypeScript 7 emits the same JavaScript as TypeScript 5 (checked by diffing `dist/`).
- **better-sqlite3 11 → 13:** needs Node.js 22 or newer. It has no install script any more and ships prebuilt N-API binaries for linux and linuxmusl (x64 and arm64), so the builder no longer installs `build-base` and `python3`. If a later version needs compiling again, add both back to the builder's `apk add`. The package is bigger (about 27 MB, with the SQLite sources and the binaries for all platforms).
- **glob 11 → 13:** no code change; `glob('**/*.md', { cwd, ignore })` works as before.
- **glob 13 → 14** (add-on 0.8.0): no code change either. glob 14 uses minimatch 11 and matches with `@isaacs/nonrecursive-glob-match` instead of regular expressions; `ignore` patterns starting with `/` changed meaning, ours (`**/CLAUDE.md`, `**/CHANGELOG.md`) do not start with `/`. Same file count, same `tools/list`, same search results and same `dist/` as with glob 13.

## ttyd and the browser scripts

The web terminal is the Alpine package `ttyd` (1.7.7, with xterm.js 5 inside). The add-on adds its own scripts to ttyd's page:

- `addon/Dockerfile`: right after the package install, starts ttyd once on a UNIX socket and saves its page as `/usr/share/ttyd-addon/ttyd-index.html`. If the page has no `window.term=`, the file is dropped and the add-on runs with ttyd's own page.
- `addon/rootfs/etc/s6-overlay/s6-rc.d/ttyd/run`: puts `reconnect.js` before `</head>` (it must run before ttyd's code, which is one inline script in `<body>`) and the other scripts from `/usr/share/ttyd-addon/` before `</body>`, then starts ttyd with `--index`. On any failure it logs a warning and uses ttyd's own page.
- `addon/rootfs/usr/share/ttyd-addon/reconnect.js`: replaces `window.WebSocket` with a subclass that watches ttyd's socket (protocol `tty`). When it stays closed for 2 s and the page is visible, it fetches ttyd's `<page path>/token`: 200 reloads the terminal page (at most 3 times a minute), 401/403 means the Ingress session expired and reloads the top page, Home Assistant (at most once a minute, counted in `sessionStorage`), anything else retries with a backoff of 2 s to 30 s. Background: Home Assistant renews the Ingress cookie only every 60 s while its own page runs (`hassio-ingress-view`, `/ingress/validate_session`, else `/ingress/session`), and ttyd 1.7.7 sets `doReconnect = false` on a WebSocket error, so its "Press ⏎ to Reconnect" keeps failing with the expired cookie (Supervisor log: `No valid ingress session`, twice per Enter: token and WebSocket).
- `addon/rootfs/usr/share/ttyd-addon/clipboard.js`: OSC 52 handler (copy into the browser clipboard). It uses only the public xterm.js API on `window.term`.
- `addon/rootfs/usr/share/ttyd-addon/touch-scroll.js` (only with the option `mobile_scroll`): turns a vertical swipe into one mouse wheel event per text row of finger travel, dispatched on `.xterm-screen`. It listens in the capture phase on the parent of the terminal element, so the touch handlers of xterm.js never see a swipe; taps and two-finger gestures pass through.
- The workflow fails if the saved page is missing or has no `window.term=`, `</head>`, `</body>`, `["tty"]` (WebSocket protocol) or `"/token"`, so a ttyd update that changes the page shows up in the test build.

When a new ttyd version reaches Alpine:

- **Clipboard:** ttyd's main branch already loads `@xterm/addon-clipboard` (not in 1.7.7). Once a release with it is in the image, remove `clipboard.js`, or two handlers copy the same text.
- **Touch scrolling:** xterm.js sends touch scrolls as wheel reports itself on its main branch (milestone 7.0, not released). Once ttyd ships it, remove `touch-scroll.js` and the option `mobile_scroll` (add it to `removed_options` in `init-claude`).
- **Reconnect:** check that ttyd still opens its WebSocket with the protocol `tty`, still computes the token address as `<page path>/token`, and whether a new release reconnects after an expired session by itself; then `reconnect.js` can go.
- Check that `window.term` still exists and the scripts still attach (browser console: `window.term.claudeCodeClipboard` and, with `mobile_scroll` on a touch screen, `window.term.claudeCodeTouchScroll` are `true`).

Test locally without Docker: download the static ttyd binary of the same version from its GitHub release (check its SHA-256), run `ttyd -i lo -W -p <port> --index <page> tmux …`, and drive it with Playwright (Chromium is preinstalled in cloud sessions). Bind to `lo`, never to all interfaces: the terminal is a writable shell. `tmux load-buffer -w -` is what Claude Code runs to copy inside tmux. For swipes, emulate a phone (`devices['Pixel 7']`) and send touch events through CDP (`Input.dispatchTouchEvent`); a small program that turns on mouse tracking (`\e[?1000h\e[?1006h`) and logs its input stands in for Claude Code (wheel up `\e[<64;`, down `\e[<65;`).

## Test without Docker

Claude Code cloud sessions cannot build the image: Docker starts, but image layers from `ghcr.io` (blob storage) are blocked, Docker Hub answers with a rate limit, and `dl-cdn.alpinelinux.org` is blocked too. Build the image with the test run of the Action, and test the MCP server locally with Node.js:

```bash
cd addon/mcp-server
npx -y pnpm@11 install --frozen-lockfile
npx tsc
DOCS_DB_PATH=$PWD/data/docs-search.db DOCS_PATH=$PWD/../../docs node --import tsx src/build-index.ts
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | DOCS_DB_PATH=$PWD/data/docs-search.db node dist/index.js | jq -S 'select(.id == 2) | .result' > tools-after.json
```

Do the same on a copy of the old state and `diff` the two `tools/list` results; also diff `dist/*.js` when the compiler changes. `.github/scripts/mcp-smoke-test.sh` runs `docker run … node /opt/mcp-server/dist/index.js`; for a local run, put a small `docker` script first in `PATH` that runs `node dist/index.js` in the server directory instead.

The smoke test in the workflow checks the docs search (with a dot and a typo), that `tools/list` describes `call_service.data` as an object, and that `call_service` with valid input fails only at the HTTP request (the container has no network and no Home Assistant), while invalid input fails with a validation error.

## Decisions and conventions

- **Permission rule paths:** in Claude Code `Read(...)`/`Edit(...)` rules, `//path` is absolute, a single leading `/path` is relative to the settings source (for `~/.claude/settings.json` it means `~/.claude/path`). Always write `//homeassistant/...`. Only `Edit(...)` and `Read(...)` path rules match; `Write(path)` and `NotebookEdit(path)` never do. Deny rules also cover file commands Claude Code recognizes in Bash (`cat`, `sed`, `tee`, redirections), not every program that opens files itself.
- **Ideas from LuckyTriple7/HA-AddOns (compared 2026-11-04):** (1) deny rules for Home Assistant's internal files: done in 0.9.0. (2) copy into the browser clipboard: 0.10.0, dktzde/hass-claude-code#48, with a browser script instead of `set-clipboard on`/`allow-passthrough on` (tested: they do not help with ttyd 1.7.7). `escape-time` (10 ms is the default since tmux 3.5) and `assume-paste-time 0` were left out. (3) swipe to scroll on a phone: 0.11.0, dktzde/hass-claude-code#49, own script (option `mobile_scroll`, default off) on the same page mechanism as 0.10.0. Not solvable in tmux (tmux never sees touch events). xterm.js has the fix on its main branch (milestone 7.0, touch scroll sent as wheel reports when the app wants mouse events; 6.0.0 even has a touch regression), ttyd's main branch is on xterm.js 5.5 and has the clipboard addon, and ttyd has not released since 1.7.7 (March 2024). Upstream route later: once xterm.js 7 is out, a PR to ttyd for the update, then a ttyd release and the Alpine package; then drop our scripts. (4) `addon/DOCS.md` for the Documentation tab: dktzde/hass-claude-code#47. (5) a notification when a newer Claude Code exists: **rejected by the maintainer** (2026-11-04). Not wanted either: `full_access`/`docker_api`, a direct port without Ingress, self-update at runtime, unpinned `latest` downloads.
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
  - Pull requests that change `addon/` or `.github/` are test-built for `amd64` and `aarch64` by the workflow "Test build" on their own.
  - Before merging a change to the update workflow, the base image or the npm majors, also run the Action by hand on the PR branch (Run workflow → choose the branch). That run never pushes and never changes issues; its step summary shows what it would release and which issues it would open or close.
  - After merging, run it on `main` once, so the release has the current package list.
- **Dependabot** (since 2026-11-10): only for the actions used in the workflows (`.github/dependabot.yml`, monthly, PRs with prefix `ci:`); such a PR needs no add-on version, nothing in the image changes. Dependabot alerts (security warnings for the npm lockfile) are on, automatic security fix PRs are off. Everything in the add-on stays with the weekly Action, because Dependabot knows neither the Claude Code pin, the Alpine packages nor the docs, and opens no release with version bump and changelog.
- **GitHub releases** (since 2026-11-23): one release `v<version>` per add-on version, with the changelog entry as notes (`.github/scripts/release.sh`). Merges and pushes to `main` publish it through `release.yml`; the weekly Action publishes it in its `release` job, because its push with `GITHUB_TOKEN` starts no other workflow. Versions before the first release have none. The Supervisor ignores releases and builds from `main`.
- **Report scripts** (`.github/scripts/`) exit with an error instead of printing nothing when a data source is down, so an outage never closes an issue.
- **Issue titles** are the key the workflow finds its issues by. When a title changes, add the old one to `retitle_issue` (or the failure job's lookup), so the open issue is renamed instead of a second one opened. The German titles there can go once no open issue carries them.

## Known issues and backlog

- **`aarch64` (Raspberry Pi) is tested by CI only** (since 2026-11-23). The maintainer has no `aarch64` hardware. The workflow "Test build" builds and checks pull requests for both architectures, and the weekly job `test-arm` builds the release commit on a native `ubuntu-24.04-arm` runner (free for public repositories; no QEMU, which was too slow). A failing `test-arm` holds back the weekly release for both architectures, so both always get the same version. Nothing runs the add-on itself on `aarch64` (s6, ttyd, tmux); the checks only start Claude Code, Python, the tools and the MCP server in the image.
- `addon/README.md` does not exist, so the add-on overview in the store shows only the description. `url` in `config.yaml` links to this repository. `addon/DOCS.md` (Documentation tab) exists since dktzde/hass-claude-code#47; keep it in step with the README (options, tips, paths) and keep it short, the README has the details.
- The option `additional_packages` installs packages on every start (needs internet, start fails if a package is missing).
- **Docs search** is SQLite FTS5 with fallbacks and typo correction. Alternatives such as MiniSearch, Fuse.js or Typesense were considered; FTS5 plus its own vocabulary needs no new dependency and keeps the index built at image build time.
- The semantic doc search was **removed** in 0.3.0 at the maintainer's request (Claude does not need it; it never worked because the docs were never indexed with embeddings). Do not bring back Transformers.js, ONNX Runtime or sqlite-vec without a new decision. On 2026-11-10 the old search service of the `hass-dev-docs` skill (`.claude/skills/hass-dev-docs/service/`, Express + sqlite-vec + Transformers.js, not part of the image) was removed as well; the skill and the `hass-docs-search` subagent now search with `rg`. Trigger: Dependabot alert #1 (`glob`, dismissed as not used).
- Prebuilt images (building in CI and pulling instead of building on the device) were considered and **rejected** for now. Building on the device works, and the stamps solve the layer cache problem.
- better-sqlite3 13 adds about 15 MB to the image (SQLite sources and prebuilt binaries for all platforms). The builder could delete `deps/`, `src/` and the binaries of other platforms after `pnpm prune --prod`; not done, to keep the build simple.
- Claude Code cloud sessions cannot build the image (image layers from `ghcr.io`, Docker Hub and the Alpine CDN are blocked or rate-limited there). Build with the test run of the Action; `MAINTENANCE.md` shows how to test the MCP server locally with Node.js.
