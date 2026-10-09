# Maintenance: base image and npm major updates

Checklists and pitfalls for the updates the weekly Action only reports as issues: a new base image (often a new Alpine version) and new major versions of the MCP server's npm dependencies. The routine updates (Claude Code, Alpine packages, npm within the majors, docs) run on their own, see "Updates" in the [README](README.md).

Each section ends with what went wrong or nearly went wrong last time, so the next update does not trip over it again. Add to it after every such update.

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

- `addon/Dockerfile`: `ARG BUILD_FROM=ghcr.io/hassio-addons/base:<version>`. The current Supervisor builder reads only this.
- `addon/build.yaml`: the same version for both architectures. Older Supervisors still read `build_from` from it.
- `addon/Dockerfile`, builder stage: `FROM alpine:<X.Y> AS mcp-builder`, the same Alpine version as the base image.

Checks:

- **Same Alpine in builder and base image.** The builder runs `pnpm install` and copies `node_modules` into the add-on. pnpm picks platform packages (and better-sqlite3 its prebuilt binary) for the builder's libc (musl) and Node.js, so both stages must match. better-sqlite3 13 uses N-API binaries that work across Node.js majors, but musl versus glibc still matters.
- **Do all packages exist under the same names?** `apk add` in the Dockerfile fails otherwise, and so does the test run. Without Docker, read the APKBUILD files on the `<X.Y>-stable` branch of the aports mirror: `https://raw.githubusercontent.com/alpinelinux/aports/3.24-stable/<main|community>/<package>/APKBUILD` (`pkgver`, `subpackages`). `mosquitto-clients` is a subpackage of `mosquitto`, `libgcc` and `libstdc++` are subpackages of `gcc`.
- **Python and Node.js versions.** Read `pkgver` of `main/python3` and `main/nodejs` there. A new Python version gets a changelog line (users may run their own scripts). A new Node.js major means `@types/node` must follow, see below.
- **Base image release notes.** Look at the changes of `hassio-addons/app-base` between the two tags (bashio, s6-overlay, tempio versions in `base/Dockerfile`). Then search `addon/rootfs` for every `bashio::` function that changed.
- **Support dates in the issue.** The base image issue also opens without a new base image, 30 days before the community repository of the installed Alpine version stops getting updates. Until the next Alpine version is out, that date is estimated as release date + 6 months.

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
