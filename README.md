# Claude Code for Home Assistant (dktzde fork)

> **Fork von [dkmaker/hass-claude-code](https://github.com/dkmaker/hass-claude-code)**
>
> **Warum?** Das Original installiert Claude Code beim Build immer als „latest“. Der HA-Supervisor baut Add-ons aber **mit Docker-Layer-Cache** (`docker buildx build --pull`, ohne `--no-cache`) auf einem fest gepinnten Basis-Image. Dadurch bleibt die Installations-Schicht gecacht: Auch „Rebuild“ liefert immer wieder die alte Claude-Code-Version.
>
> **Was ist geändert?**
> - `addon/Dockerfile`: Claude Code wird über `ARG CLAUDE_CODE_VERSION` fest versioniert installiert (aktuell **2.1.280**). Eine neue Version dort eintragen invalidiert den Cache, und die neue Version wird installiert.
> - `addon/config.yaml`: Add-on-Version erhöht, damit HA das Update anbietet.
> - `repository.yaml`, `DOCS_REPO`, Links in dieser README: zeigen auf diesen Fork.
>
> **Übernommen aus [YangXu1990uiuc/hass-claude-code](https://github.com/YangXu1990uiuc/hass-claude-code)** (Stand 2026-09):
> - **pnpm-11-Build-Fix**: Das Original bricht mit aktuellem pnpm beim Build ab (`ERR_PNPM_IGNORED_BUILDS`). Fix: `pnpm-workspace.yaml` mit `allowBuilds`, pnpm auf Major 11 gepinnt.
> - **Login bleibt erhalten**: Im Original landete `/root/.claude` durch einen Symlink-Fehler nicht in `/data`, dadurch waren Login, Verlauf und Memory nach jedem Neustart weg.
>
> **Claude Code aktualisieren:** `CLAUDE_CODE_VERSION` in `addon/Dockerfile` und `version` in `addon/config.yaml` erhöhen, pushen, in HA auf „Update“ klicken.

A Home Assistant add-on that runs [Claude Code](https://docs.anthropic.com/en/docs/claude-code) inside your HA instance with a web terminal, full API access, and a built-in MCP server providing structured tools for interacting with your smart home.

## Features

- **Web terminal** via Home Assistant Ingress (no port forwarding needed)
- **Full HA API access** — search entities, call services, query devices/areas
- **Built-in documentation search** — HA developer and user docs indexed and searchable
- **Session persistence** — tmux keeps your Claude session alive across browser tab closes
- **MCP server** with 11 tools for Home Assistant interaction
- **Optional semantic search** — enable embeddings for AI-powered doc search

## Installation

### 1. Add the repository

[![Open your Home Assistant instance and show the add add-on repository dialog.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fdktzde%2Fhass-claude-code)

Or manually:

1. Go to **Settings** > **Add-ons** > **Add-on Store**
2. Click the **three-dot menu** (top right) > **Repositories**
3. Add: `https://github.com/dktzde/hass-claude-code`
4. Click **Save**, then refresh

### 2. Install the add-on

1. Find **Claude Code** in the add-on store
2. Click **Install** (the Docker image builds locally on your device — this takes a few minutes on first install)
3. Go to the **Configuration** tab and set your **Anthropic API key**
4. Click **Start**
5. Open the **Claude Code** panel in the sidebar

### How the build works

Home Assistant builds the Docker image **locally on your device** when you install the add-on. There are no pre-built images to pull. The build process:

1. Installs Node.js dependencies for the MCP server
2. Clones the HA documentation from this repository
3. Builds a keyword search index from the docs
4. Installs Claude Code CLI, ttyd, tmux, and other tools
5. Sets up s6-overlay services for process management

First install takes several minutes depending on your hardware. Subsequent updates are faster due to Docker layer caching — which is also why the Claude Code version is pinned (see the fork note at the top).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `api_key` | password | *required* | Your Anthropic API key |
| `model` | string | *(empty)* | Claude model to use (leave empty for default) |
| `yolo_mode` | bool | `false` | Skip permission prompts (use with caution) |
| `enable_embeddings` | bool | `false` | Download AI model for semantic doc search (~87MB) |
| `additional_packages` | list | `[]` | Extra Alpine packages to install (e.g. `python3`, `vim`) |

## MCP Tools

The built-in MCP server (`home-assistant`) provides these tools to Claude:

| Tool | Description |
|------|-------------|
| `search_entities` | Search entities by name, domain, or area |
| `get_entity_state` | Get state and attributes of a specific entity |
| `call_service` | Call any HA service (turn on lights, run automations, etc.) |
| `search_automations` | Search automation entities |
| `get_ha_config` | Get Home Assistant core configuration |
| `list_areas` | List all defined areas |
| `search_devices` | Search the device registry |
| `get_config_entries` | List integration config entries |
| `search_docs` | Search HA developer and user documentation |
| `read_doc` | Read a specific documentation file |
| `get_doc_stats` | Get documentation index statistics |

## File Access

The add-on has access to:

| Path | Description | Access |
|------|-------------|--------|
| `/homeassistant/` | HA configuration directory (including `.storage/`) | Read/Write |
| `/config/` | Add-on configuration | Read/Write |
| `/share/` | Shared storage between add-ons | Read/Write |
| `/ssl/` | SSL certificates | Read-only |
| `/media/` | Media files | Read-only |

## Architecture

```
addon/
  config.yaml              # HA add-on manifest
  Dockerfile               # Multi-stage build
  build.yaml               # Base images per architecture
  rootfs/                  # Container filesystem overlay
    etc/s6-overlay/        # s6 service definitions
    usr/bin/               # Claude entrypoint script
  mcp-server/              # Node.js MCP server
    src/
      index.ts             # MCP entry point (stdio transport)
      ha-api.ts            # HA REST API tools
      ha-websocket.ts      # HA WebSocket API tools
      docs-search.ts       # Documentation search tools
      db.ts, search.ts, embeddings.ts, indexer.ts  # Search engine
```

The MCP server runs as a stdio child process of Claude Code (configured via `.mcp.json`). No separate network port needed.

## Development

To test locally without HA:

```bash
# Build the Docker image
docker build -t claude-code-addon addon/

# Run with your API key
docker run -it \
  -e SUPERVISOR_TOKEN=fake \
  -e ANTHROPIC_API_KEY=your-key \
  claude-code-addon
```

## Supported Architectures

- `amd64` (x86_64)
- `aarch64` (ARM64, e.g. Raspberry Pi 4/5)
