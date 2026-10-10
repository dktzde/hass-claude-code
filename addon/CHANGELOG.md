## 0.4.2

### Bug fixes

- The MCP tools `list_areas`, `search_devices` and `get_config_entries` always returned an empty list. They sent their websocket commands as a REST `POST` to `/core/api`, which Home Assistant answers with 405, and the error was hidden behind the empty list. They now use the websocket API through the Supervisor (`ws://supervisor/core/websocket`) and return the areas, devices and config entries. If Home Assistant cannot be reached, the tool reports the error instead of an empty list

## 0.4.1

- **Automated update** by the GitHub Action "Update add-on" ([workflow run](https://github.com/dktzde/hass-claude-code/actions/runs/37985313879))
- Update Claude Code to 2.1.296
- Update system packages: `alpine-baselayout-3.7.2-r1`, `alpine-baselayout-data-3.7.2-r1`, `alpine-release-3.24.2-r0`, `bash-5.3.9-r1`, `brotli-libs-1.2.0-r1`, `busybox-1.37.0-r31`, `busybox-binsh-1.37.0-r31`, `curl-8.22.0-r0`, `git-2.54.0-r0`, `git-init-template-2.54.0-r0` and 32 more

## 0.4.0

New minor version because of the new Alpine version and the new major versions of the MCP server's dependencies.

### Changes

- New base image `ghcr.io/hassio-addons/base` 21.0.8 with **Alpine 3.24** (was 20.0.1 with Alpine 3.23). The community repository of Alpine 3.23, which has ttyd, ripgrep and the GitHub CLI, got no more updates since June 2026; with Alpine 3.24 these tools get updates again
- **Python 3.14** (was 3.12). PyYAML is still included. If you run your own Python scripts in the add-on, they now run on Python 3.14
- Node.js stays at version 24
- Newer versions of the tools that come from Alpine, for example the GitHub CLI, tmux, git and the MQTT clients
- The built-in MCP server uses new major versions of its libraries (better-sqlite3 13, zod 4, glob 13, TypeScript 7). The tools work as before
- The build no longer installs a compiler, because better-sqlite3 now comes with prebuilt binaries. The first build after an update downloads less, which helps most on a Raspberry Pi
- The add-on log shows no deprecation warning from the new base image (`bashio::addon.ingress_port` is now `bashio::app.ingress_port`)

## 0.3.4

- **Automated update** by the GitHub Action "Update add-on" ([workflow run](https://github.com/dktzde/hass-claude-code/actions/runs/37977993166))
- Update the bundled Home Assistant docs (12 files changed)

## 0.3.3

- **Automated update** by the GitHub Action "Update add-on" ([workflow run](https://github.com/dktzde/hass-claude-code/actions/runs/37906784853))
- Update Claude Code to 2.1.295
- Update npm dependencies of the MCP server: `@hono/node-server@2.1.4`, `node-abi@3.98.0`
- Update the bundled Home Assistant docs (9 files changed)

## 0.3.2

- **Automated update** by the GitHub Action "Update add-on" ([workflow run](https://github.com/dktzde/hass-claude-code/actions/runs/37776922455))
- Update Claude Code to 2.1.293
- Update the bundled Home Assistant docs (35 files changed)

## 0.3.1

### Bug fixes

- Yolo mode: remove `"permissions.defaultMode": "acceptEdits"` from the managed settings. It was written as one key with a dot, so Claude Code never read it, and yolo mode always worked through the allow list alone. Written correctly, it would make every session start in "accept edits" and override the mode users choose in their own settings, so it is removed instead of fixed
- The generated `/etc/claude-code/CLAUDE.md` named `GET /core/api/error_log` for the error log, which returns 404 on Home Assistant OS (Core writes no `home-assistant.log` there). It now points to the Supervisor endpoint `/core/logs`, with `?lines=500` and `/core/logs/latest`

## 0.3.0

### Breaking change

- Remove the semantic doc search and its option **Semantic doc search** (`enable_embeddings`). It never worked: the model was downloaded, but the docs were never indexed with it, so the search always fell back to keyword search. The downloaded model (about 87 MB in `/data/models`) is deleted on the first start of this version

### Improvements

- The add-on image is about 350 MB smaller: the embedding libraries (Transformers.js, ONNX Runtime, sharp, sqlite-vec) are gone
- The keyword search now handles queries with dots and dashes, such as `light.turn_on`, `ConfigEntry.runtime_data` or `config-flow`. They used to fail with an FTS5 syntax error; now they are split into words (all words first, then any word)
- The keyword search corrects typos when nothing matches: words that do not occur in the docs are replaced by the closest word that does (`light.tun_on` → `light turn_on`, `automaton` → `automation`), and the result says which query was used
- Stored values of removed options (`api_key` from 0.1.x, `enable_embeddings` from 0.2.x) are removed from the add-on configuration on start. Before, Home Assistant kept them, for example in the YAML editor of the configuration tab, until the configuration was saved again

## 0.2.1

- **Automated update** by the GitHub Action "Update add-on" ([workflow run](https://github.com/dktzde/hass-claude-code/actions/runs/37633199475))
- Update system packages: `cjson-1.7.19-r1`, `github-cli-2.83.0-r6`, `mosquitto-clients-2.0.22-r0`, `mosquitto-libs-2.0.22-r0`, `py3-yaml-6.0.3-r0`, `py3-yaml-pyc-6.0.3-r0`, `yaml-0.2.5-r2`

## 0.2.0

New minor version because of the many changes since 0.1.15: Python 3 and more tools, weekly updates of packages, npm dependencies and docs, a generated `CLAUDE.md` and login only through Claude Code.

### Breaking change

- Remove the API key option. Claude Code asks you to log in on first start, with a Claude subscription or an Anthropic Console account. If you used an API key, log in once after this update; the login is kept across restarts

### Improvements

- Include PyYAML (`py3-yaml`), so Claude Code can read and check YAML files with Python
- Include the MQTT clients `mosquitto_pub` and `mosquitto_sub` (`mosquitto-clients`), to inspect and test MQTT devices
- Include the GitHub CLI (`gh`). Its login and the global git config are now kept in `/data` across restarts
- All three are Alpine packages, so the weekly GitHub Action keeps them up to date like Python 3 itself
- Claude Code now knows its environment: on every start the add-on writes `/etc/claude-code/CLAUDE.md` with the paths, MCP tools, APIs, command line tools and rules for editing the configuration. Claude Code loads it automatically, also on existing installs
- `/homeassistant/CLAUDE.md` is now for your own notes. The add-on creates it only when it is missing and never changes an existing one
- With the Mosquitto broker add-on installed, the add-on gets the broker credentials from Home Assistant and passes them to Claude Code as `MQTT_HOST`, `MQTT_PORT`, `MQTT_USERNAME` and `MQTT_PASSWORD`
- The configuration tab has names and descriptions in English and German

### Bug fixes

- Fix the dead "more information" link on the add-on page in Home Assistant: `config.yaml` had no `url`, it now points to the GitHub repository

## 0.1.18

### Improvements

- Pin the npm dependencies of the MCP server with a lockfile, so every device builds exactly the versions that were tested instead of whatever npm offers at build time
- The weekly GitHub Action now also updates these dependencies within their major versions and checks the MCP server after each test build (tool list and a docs search)
- New major versions of npm dependencies and new versions of the base image are reported as issues in this repository; switching to them stays a manual step

## 0.1.17

- **Automated update** by the GitHub Action "Update add-on" ([workflow run](https://github.com/dktzde/hass-claude-code/actions/runs/37606435542))
- Update Claude Code to 2.1.292
- Update system packages: `ada-libs-3.3.0-r0`, `alpine-baselayout-3.7.2-r0`, `alpine-baselayout-data-3.7.2-r0`, `alpine-keys-2.6-r0`, `alpine-release-3.23.6-r0`, `apk-tools-3.0.8-r0`, `bash-5.3.3-r1`, `brotli-libs-1.2.0-r0`, `busybox-1.37.0-r30`, `busybox-binsh-1.37.0-r30` and 55 more
- Update the bundled Home Assistant docs (320 files changed)

## 0.1.16

### Improvements

- Include Python 3 in the add-on image, so Claude Code can run `python3` without the `additional_packages` option
- Keep system packages up to date: the weekly GitHub Action now also releases Alpine package updates (including Python 3), and the build runs `apk upgrade` so packages from the base image are updated too
- Keep the bundled Home Assistant docs up to date: the weekly GitHub Action regenerates them from the upstream repositories, and a docs change now reaches the add-on instead of staying in the Docker layer cache

## 0.1.15

- **Automated update** by the GitHub Action "Update Claude Code" ([workflow run](https://github.com/dktzde/hass-claude-code/actions/runs/37191988233))
- Update Claude Code to 2.1.289

## 0.1.14

- **Automated update** by the GitHub Action "Update Claude Code" ([workflow run](https://github.com/dktzde/hass-claude-code/actions/runs/37110577797))
- Update Claude Code to 2.1.288

## 0.1.13

- Update Claude Code to 2.1.283

## 0.1.12

### Improvements

- Pin Claude Code to 2.1.280 via `CLAUDE_CODE_VERSION` build arg
  - Previously the installer always fetched "latest", but the Docker layer was cached, so rebuilds kept the old version
  - Bumping the pinned version now forces a fresh install on update
- Point docs clone and repository metadata at the `dktzde` fork

### Bug fixes (from YangXu1990uiuc/hass-claude-code)

- Fix Docker build failure with pnpm 11 (`ERR_PNPM_IGNORED_BUILDS`, #4): move the
  dependency build-script allowlist from the no-longer-read `pnpm` field in
  package.json to `allowBuilds` in `pnpm-workspace.yaml`
- Pin pnpm to major version 11 so future pnpm releases can't silently break the build
- Stop hiding pnpm install errors behind `2>/dev/null`; pick frozen vs regular
  install based on whether a lockfile is present
- Persist Claude Code login, sessions and memory across add-on restarts: replace the
  installer's `/root/.claude` directory with the `/data` symlink (`ln -sfn`) instead of
  creating a nested link inside it

## 0.1.11

### Improvements

- Trim MCP tool responses to return only essential fields instead of full objects
  - `search_entities`: returns entity_id, state, name, area (use `get_entity_state` for full attributes)
  - `search_automations`: returns entity_id, state, name, last_triggered
  - `search_devices`: returns id, name, area_id, manufacturer, model
  - `list_areas`: returns area_id, name, floor_id
  - `get_config_entries`: returns entry_id, domain, title, state
  - `call_service`: returns success message instead of full response objects
  - `get_ha_config`: returns only useful config fields instead of entire object
- Add all MCP tools to yolo mode allow list

## 0.1.10

### Bug fixes

- Revert non-root user approach (would break HA file permissions)
- Yolo mode now uses managed-settings.json to allow all tools instead of `--dangerously-skip-permissions` (which is blocked as root)
- No chown/chmod on HA-mounted directories — permissions are untouched

## 0.1.9

### Bug fixes

- Fix yolo mode: run Claude Code as non-root `claude` user (required for `--dangerously-skip-permissions`)
- Grant claude user write access to HA config, share, and addon config directories
- Persistent data (`.claude/`, `.claude.json`, history) now owned by claude user

## 0.1.8

### Improvements

- Make API key optional — leave blank and use `/login` in Claude Code to authenticate via subscription (Pro/Max)

## 0.1.7

### Bug fixes

- Fix better-sqlite3 native module crash: use Alpine 3.23 with Node 24 in builder to match runtime environment
- Fix yolo mode not working: write config to env vars in `/etc/profile.d/` instead of relying on bashio in tmux context
- Simplify entrypoint to use env vars (`CLAUDE_MODEL`, `CLAUDE_YOLO`) instead of bashio calls

## 0.1.6

### Bug fixes

- Compile MCP server TypeScript to JavaScript at build time instead of running via tsx at runtime
- Fix corrupt `.claude.json` on first start (initialize with `{}` instead of empty file)
- Remove npm from final image (no longer needed with binary installer)
- Prune dev dependencies from final image for smaller size

## 0.1.5

### Bug fixes

- Persist `~/.claude.json` across restarts (symlinked to `/data/.claude.json`)

## 0.1.4

### Bug fixes

- Fix MCP server not loading: use `/etc/claude-code/managed-mcp.json` (system-wide) instead of `.mcp.json` in home dir which Claude Code doesn't find when working dir differs
- Switch to official Claude Code binary installer (`curl -fsSL https://claude.ai/install.sh | bash`) instead of npm

## 0.1.3

### Improvements

- Model config is now a dropdown: default, sonnet, opus, haiku
- Uses Claude Code short aliases that auto-resolve to latest model versions

## 0.1.2

### Bug fixes

- Fix 502 Bad Gateway on Ingress: bind ttyd to 0.0.0.0 instead of `hassio` interface (which only exists with `host_network: true`)

## 0.1.1

### Bug fixes

- Fix Docker build failures with native module loading
- Make sqlite-vec loading conditional on ENABLE_EMBEDDINGS to avoid .so errors at build time
- Use lazy dynamic import for @huggingface/transformers to prevent onnxruntime-node load at import time
- Allow pnpm to build better-sqlite3 native bindings via onlyBuiltDependencies config

## 0.1.0

### Initial release

- Web terminal via Home Assistant Ingress (ttyd + tmux)
- Built-in MCP server with 11 tools:
  - `search_entities`, `get_entity_state`, `call_service`
  - `search_automations`, `get_ha_config`
  - `list_areas`, `search_devices`, `get_config_entries`
  - `search_docs`, `read_doc`, `get_doc_stats`
- Pre-indexed HA developer and user documentation (FTS5 keyword search)
- Optional semantic search with embeddings (~87MB model, opt-in)
- Session persistence across browser tab closes
- Configurable model, yolo mode, and additional Alpine packages
- Full access to HA config, shared storage, SSL, and media directories
