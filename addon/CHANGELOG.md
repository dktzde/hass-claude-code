## 0.1.17

- **Automated update** by the GitHub Action "Update add-on" ([workflow run](https://github.com/dktzde/hass-claude-code/actions/runs/37606435542)), not made by hand
- Update Claude Code to 2.1.292
- Update system packages: `ada-libs-3.3.0-r0`, `alpine-baselayout-3.7.2-r0`, `alpine-baselayout-data-3.7.2-r0`, `alpine-keys-2.6-r0`, `alpine-release-3.23.6-r0`, `apk-tools-3.0.8-r0`, `bash-5.3.3-r1`, `brotli-libs-1.2.0-r0`, `busybox-1.37.0-r30`, `busybox-binsh-1.37.0-r30` and 55 more
- Update the bundled Home Assistant docs (320 files changed)

## 0.1.16

### Improvements

- Include Python 3 in the add-on image, so Claude Code can run `python3` without the `additional_packages` option
- Keep system packages up to date: the weekly GitHub Action now also releases Alpine package updates (including Python 3), and the build runs `apk upgrade` so packages from the base image are updated too
- Keep the bundled Home Assistant docs up to date: the weekly GitHub Action regenerates them from the upstream repositories, and a docs change now reaches the add-on instead of staying in the Docker layer cache

## 0.1.15

- **Automated update** by the GitHub Action "Update Claude Code" ([workflow run](https://github.com/dktzde/hass-claude-code/actions/runs/37191988233)), not made by hand
- Update Claude Code to 2.1.289

## 0.1.14

- **Automated update** by the GitHub Action "Update Claude Code" ([workflow run](https://github.com/dktzde/hass-claude-code/actions/runs/37110577797)), not made by hand
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
