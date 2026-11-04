# Claude Code

This add-on runs [Claude Code](https://docs.anthropic.com/en/docs/claude-code) inside Home Assistant. Open **Claude Code** in the sidebar to get a web terminal. Claude can read and change your configuration, look up entities, devices and areas, call services and search the bundled Home Assistant docs.

The [README](https://github.com/dktzde/hass-claude-code#readme) has all the details. This page covers what you need in daily use.

## First start

1. Start the add-on and open **Claude Code** in the sidebar.
2. Log in when Claude Code asks for it, with your Claude subscription or an Anthropic Console account. The login is kept across restarts and updates.
3. On a phone, the login URL is hard to copy. Turn on **Mobile login**, restart the add-on, and tap the link in the Home Assistant notification instead.

## Options

- **Model**: the Claude model, `default`, `sonnet`, `opus` or `haiku`.
- **Protect internal files** (on by default): Claude Code cannot change Home Assistant's internal files under `/homeassistant/`. These are `.storage/` (registries, UI automations, dashboards, helpers), `.cloud/`, `deps/`, `tts/` and the recorder database `home-assistant_v2.db`. A broken `.storage/` file can keep Home Assistant from starting. Reading them still works. Turn the option off only to repair such a file on purpose. Scripts that open files themselves, for example Python or `sqlite3`, are not blocked; Claude is told not to use them for it.
- **Mobile login**: send the login link as a notification while Claude Code waits for the login.
- **Mobile tabs**: a tappable bar at the bottom of the terminal, with one tab per Claude Code window, a `+` button for another session, ↑/↓ to scroll, ⇧⇥ (Shift+Tab, switches the Claude Code mode) and Esc.
- **Swipe to scroll**: on a touch screen, a vertical swipe on the terminal scrolls like a mouse wheel, also inside Claude Code. Taps keep working.
- **Disable mouse support**: Claude Code stops capturing the mouse, so you can select text with a finger. Mouse wheel scrolling inside Claude Code stops working.
- **Additional packages**: extra Alpine packages, installed on every start (for example `vim`).

Changes to the options take effect after a restart of the add-on.

## Tips

- **Copy:** hold <kbd>Shift</kbd> and select text with the mouse. Text that Claude Code copies itself, for example with `/copy`, lands in the browser clipboard too, also on a phone.
- **Paste:** <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>V</kbd> on Linux.
- **Sessions keep running:** tmux keeps Claude Code running when you close the browser tab. A second browser tab shows the same session.
- **Your own notes for Claude** go into `/homeassistant/CLAUDE.md`. Claude Code loads it into every session, so keep it short. The add-on describes its own environment in `/etc/claude-code/CLAUDE.md` and refreshes that file on every start.
- **Permanent tools:** packages you install with `apk add` are gone after a restart. Add them to **Additional packages** instead.
- **MQTT:** with the Mosquitto broker add-on installed, Claude gets the broker credentials as `MQTT_HOST`, `MQTT_PORT`, `MQTT_USERNAME` and `MQTT_PASSWORD`.

## Files

- `/homeassistant/`: your Home Assistant configuration. Read and write, apart from the protected files above.
- `/config/`: this add-on's own configuration folder. Read and write.
- `/share/`: storage shared between add-ons. Read and write.
- `/ssl/` and `/media/`: read-only.
- Only `/data` (login, history, memory, GitHub CLI login, git config) and these folders survive a restart.

## Updates

Home Assistant builds the add-on on your device. A GitHub Action checks every week for new versions of Claude Code, the system packages and the docs, and releases them as a normal add-on update. The changelog lists what changed.

## Help

If something does not work, check the add-on log first, then [open an issue](https://github.com/dktzde/hass-claude-code/issues).
