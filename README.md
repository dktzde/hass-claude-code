# Claude Code for Home Assistant

A Home Assistant add-on that runs [Claude Code](https://docs.anthropic.com/en/docs/claude-code) inside your Home Assistant instance. You get a web terminal in the sidebar, full access to your configuration and a built-in MCP server, so Claude can look up entities, call services and search the Home Assistant docs.

> [!WARNING]
> **Not long-term tested yet.** This fork contains several recent changes that have only been tested briefly:
> - Weekly automatic updates of Claude Code, the system packages and the bundled docs
> - Python 3 with PyYAML, the MQTT clients `mosquitto_pub`/`mosquitto_sub` and the GitHub CLI `gh` in the add-on image
> - A changed Docker build order (cache stamps for packages and docs)
> - Login only through Claude Code (the API key option is gone) and a generated `CLAUDE.md` describing the add-on
>
> The weekly test build only covers `amd64`. **Raspberry Pi and other `aarch64` devices are not tested.**
>
> If something breaks after an update, please [open an issue](https://github.com/dktzde/hass-claude-code/issues).

## Thanks

This add-on would not exist without two other projects:

- **[dkmaker/hass-claude-code](https://github.com/dkmaker/hass-claude-code)** created the add-on: the web terminal, the MCP server and the documentation search. This fork builds on it.
- **[YangXu1990uiuc/hass-claude-code](https://github.com/YangXu1990uiuc/hass-claude-code)** fixed the Docker build for pnpm 11 and made the Claude Code login survive add-on restarts. Both fixes are included here.

Thank you both!

## Features

- **Web terminal** in the Home Assistant sidebar via Ingress, no port forwarding needed
- **Home Assistant access** through an MCP server: search entities, devices and areas, read states, call services
- **Documentation search** across the Home Assistant user and developer docs, bundled with the add-on. Keyword search that also copes with identifiers like `light.turn_on` and corrects typos
- **Python 3 with PyYAML** included, for the scripts Claude likes to run, for example to read YAML configuration
- **MQTT clients** `mosquitto_pub` and `mosquitto_sub`, to inspect and test MQTT devices. With the Mosquitto broker add-on installed, the add-on gets the broker credentials from Home Assistant and passes them to Claude as `MQTT_HOST`, `MQTT_PORT`, `MQTT_USERNAME` and `MQTT_PASSWORD`
- **GitHub CLI** `gh`, for example to keep your configuration in a GitHub repository
- **Knows its environment**: on every start the add-on writes `/etc/claude-code/CLAUDE.md`, which Claude Code loads automatically. It lists the paths, MCP tools, APIs and command line tools. Your own notes for Claude go into `/homeassistant/CLAUDE.md`
- **Persistent sessions**: tmux keeps Claude running when you close the browser tab. The Claude Code login, history and memory, the GitHub CLI login and the git config survive restarts
- **Weekly updates** of Claude Code, system packages and docs (see [Updates](#updates))

## Quick guide

- **Copy:** hold <kbd>Shift</kbd> and select text with the mouse. The selection goes straight to the clipboard.
- **Paste:** <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>V</kbd> on Linux.
- **Second Claude session:** press <kbd>Ctrl</kbd>+<kbd>b</kbd>, then <kbd>c</kbd>. tmux opens a new window with a shell. Start Claude Code in it with:

  ```bash
  PATH=/root/.local/bin:$PATH claude-entrypoint.sh
  ```

  The new window is a login shell whose `PATH` lacks `/root/.local/bin`, so a plain `claude` ends in "claude: not found". Switch between the windows with <kbd>Ctrl</kbd>+<kbd>b</kbd>, then <kbd>n</kbd> (next) or <kbd>p</kbd> (previous). A second browser tab does not start a second session, it shows the same one.
- **Chat log:** the Stop hook in [`examples/chat-log-hook`](examples/chat-log-hook/) writes your prompts and Claude's answers into one Markdown file per day, so you can read an answer again after it has scrolled out of the terminal. Its README explains what it does and how to install it.

## Installation

1. Add the repository:

   [![Open your Home Assistant instance and show the add add-on repository dialog.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fdktzde%2Fhass-claude-code)

   Or manually: **Settings** > **Add-ons** > **Add-on Store**, three-dot menu > **Repositories**, add `https://github.com/dktzde/hass-claude-code`.
2. Find **Claude Code** in the add-on store and select **Install**. Home Assistant builds the image on your device, which takes a few minutes the first time.
3. Select **Start** and open **Claude Code** in the sidebar.
4. Log in when Claude Code asks for it on first start, with your Claude subscription or an Anthropic Console account. The login is kept across restarts and updates.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `model` | list | `default` | Model to use: `default`, `sonnet`, `opus` or `haiku` |
| `yolo_mode` | bool | `false` | Allow all tools without asking (use with caution) |
| `additional_packages` | list | `[]` | Extra Alpine packages, installed on every start (e.g. `vim`) |

## Updates

The Home Assistant Supervisor builds add-ons with the Docker layer cache. A build step only runs again if something in it changes, so a plain "install the latest version" stays at the version of the first install forever, even after a rebuild.

This add-on therefore pins everything that should update in `addon/Dockerfile`:

- `CLAUDE_CODE_VERSION`: the Claude Code version (currently **2.1.293**)
- `PACKAGES_STAMP`: a hash of `addon/packages.txt`, the list of installed Alpine package versions
- `DOCS_STAMP`: the git tree hash of the bundled docs

The npm dependencies of the MCP server are pinned by `addon/mcp-server/pnpm-lock.yaml`, which the build installs with `--frozen-lockfile`.

Every Saturday at 05:47 UTC (07:47 CEST / 06:47 CET), the GitHub Action [`update-claude-code.yml`](.github/workflows/update-claude-code.yml) does the following:

1. Checks for a new Claude Code release.
2. Regenerates the docs from the upstream Home Assistant repositories.
3. Updates the npm dependencies within their major versions.
4. Test-builds the add-on, reads the installed package versions and checks that the MCP server answers.
5. If anything changed, updates the pins, bumps the add-on version, writes the changelog and pushes.

Home Assistant then offers a normal add-on update. The changelog marks these updates as **Automated update** and lists what changed. If nothing changed, nothing is released.

Some updates stay a manual decision because they can need code changes. The same Action opens an issue for each of them:

- New commits in the two projects above, so useful fixes can be taken over by hand
- A new version of the base image `ghcr.io/hassio-addons/base`, or support of the installed Alpine version ending soon. The issue shows until when the installed Alpine version gets updates for its main and its community repository, plus the support end of Python and Node.js, with dates from [endoflife.date](https://endoflife.date)
- New major versions of npm dependencies. npm publishes no end-of-support dates, so for each package the issue shows whether its installed line still gets updates and when it got the last one

If a run fails, the Action opens the issue "Update add-on failed" with a link to the log, comments on it for each further failure and closes it after the next successful run. A failed run never publishes anything, so the add-on on your device is not affected.

To update by hand, run the `/update-claude` skill in this repository, or bump `CLAUDE_CODE_VERSION` in `addon/Dockerfile` and `version` in `addon/config.yaml`.

## MCP tools

The built-in MCP server `home-assistant` gives Claude these tools:

| Tool | Description |
|------|-------------|
| `search_entities` | Search entities by name, domain or area |
| `get_entity_state` | Get state and attributes of an entity |
| `call_service` | Call any service (turn on lights, run automations, etc.) |
| `search_automations` | Search automations |
| `get_ha_config` | Get the core configuration |
| `list_areas` | List all areas |
| `search_devices` | Search the device registry |
| `get_config_entries` | List integration config entries |
| `search_docs` | Search the user and developer docs |
| `read_doc` | Read a documentation file |
| `get_doc_stats` | Get documentation index statistics |

## File access

| Path | Content | Access |
|------|---------|--------|
| `/homeassistant/` | Home Assistant configuration, including `.storage/` | Read/write |
| `/config/` | Add-on configuration | Read/write |
| `/share/` | Storage shared between add-ons | Read/write |
| `/ssl/` | Certificates | Read-only |
| `/media/` | Media files | Read-only |

On every start, the add-on writes `/etc/claude-code/CLAUDE.md` with an overview of the paths, tools and APIs, which Claude Code loads automatically. `/homeassistant/CLAUDE.md` is for your own notes: the add-on creates it if it is missing and never changes an existing one.

## How it is built

The image is built in two stages:

1. **Builder:** installs the MCP server dependencies, clones the docs from this repository and builds a keyword search index.
2. **Add-on image:** based on the Home Assistant community add-on base image. Installs Claude Code, Python 3 with PyYAML, the MQTT clients, Node.js, ttyd, tmux and a few tools, and copies in the MCP server, the index and the docs.

s6-overlay starts the services: environment setup, optional packages, and finally ttyd, which runs Claude Code inside tmux. Claude Code starts the MCP server itself as a child process over stdio, so it needs no network port.

```
addon/
  config.yaml          # Add-on manifest
  Dockerfile           # Two-stage build with version and cache pins
  packages.txt         # Installed package versions, written by the weekly Action
  rootfs/              # s6 services and the Claude entrypoint
  mcp-server/src/      # MCP server: Home Assistant API, WebSocket API, docs search
docs/                  # Bundled Home Assistant docs, generated weekly
examples/
  chat-log-hook/       # Optional Stop hook: daily Markdown log of your chats
```

## Local development

```bash
docker build -t claude-code-addon addon/
docker run -it -e SUPERVISOR_TOKEN=fake -e ANTHROPIC_API_KEY=your-key claude-code-addon
```

## Supported architectures

- `amd64`: test-built every week by the GitHub Action
- `aarch64` (for example Raspberry Pi 4 and 5): offered, but **not tested**. The Action does not build it, so a problem would only show up when a device builds the add-on
