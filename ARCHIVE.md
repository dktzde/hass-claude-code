# Archiv: lokale Dev-Commits vom 06.03.2026 (Add-on 0.1.12)

Dieser Branch ist ein **Backup**. Er wird nicht gemergt und nicht gebaut. Er sichert sieben Commits, die bis zum 08.10.2026 nur lokal auf dem Entwicklungsrechner lagen (Branches `main` und `backup-local-dev-commits`) und nie gepusht wurden.

## Herkunft

- **Basis:** `db5c0ca`, der Stand von upstream [dkmaker/hass-claude-code](https://github.com/dkmaker/hass-claude-code) mit Add-on 0.1.11.
- **Entstanden:** 06.03.2026, lokal und mit Claude Sonnet 4.6.
- **Git-Autor der sieben Commits:** `DKMaker <dom@dkmaker.com>`, die damalige Git-Identität, nicht `dktzde`.
- **Abstand zum Fork:** Gegenüber `main` dieses Forks (0.3.1, Stand 08.10.2026) fehlen diesem Branch 40 Commits. Er ist also stark veraltet.

## Die Commits

| Commit | Inhalt | Übernehmen? |
|---|---|---|
| `4cccc4e` | ttyd-Option `-t scrollback=10000` für die Scrollbar von xterm.js | Nein. `d40f8c1` nimmt die Option wieder heraus |
| `02596d2` | Slug `claude_code_dev`, Name „Claude Code Dev“, damit es parallel zum normalen Add-on testbar ist | **Nein**, nur zum Testen |
| `c160189` | Version 0.1.12 und Changelog | **Nein** |
| `d40f8c1` | tmux `mouse on` und `history-limit 10000` (`/root/.tmux.conf`). Das xterm.js-Scrollback funktioniert nicht mit dem Alternate Screen von tmux | Siehe `874df6d` |
| `5f9cf41` | Revert von `mouse on`, weil Textauswahl und das Kopieren der Login-URL kaputt gingen | Siehe `874df6d` |
| `874df6d` | `mouse on` wieder eingeschaltet. Text markiert man jetzt mit **Shift+Ziehen**. Dazu ein Starthinweis in `claude-entrypoint.sh` | Ja, falls gewünscht |
| `3543fe4` | **ESC-Button für Mobilgeräte** über einen HTTP-Proxy. Entfernt außerdem den Starthinweis aus `874df6d` wieder (die Commit-Message nennt keinen Grund) | Ja, falls gewünscht |

## Endstand: was sich gegenüber 0.1.11 wirklich ändert

### 1. ESC-Button für Mobilgeräte

Auf Handy-Tastaturen gibt es keine Escape-Taste, Claude Code braucht sie aber, zum Beispiel zum Abbrechen.

- `addon/rootfs/usr/bin/ttyd-proxy.js` ist ein Node-Proxy mit 139 Zeilen. Er lauscht auf dem Ingress-Port und leitet an ttyd weiter.
- ttyd lauscht dafür nur noch auf `127.0.0.1:7682` statt auf `0.0.0.0` und dem Ingress-Port (`addon/rootfs/etc/s6-overlay/s6-rc.d/ttyd/run`).
- Der Proxy fügt in jede HTML-Antwort vor `</body>` einen schwebenden Button „ESC“ unten rechts ein. Damit er das HTML ändern kann, schaltet er die Kompression ab (`accept-encoding: identity`).
- Ein Tipp auf den Button schickt ein Escape-Event an xterm.js. Klappt das nicht, schickt er das Escape-Zeichen direkt über den ttyd-WebSocket.
- WebSocket-Verbindungen tunnelt der Proxy unverändert durch.
- Neuer s6-Dienst `ttyd-proxy`, der von `ttyd` abhängt: `s6-rc.d/ttyd-proxy/` und `s6-rc.d/user/contents.d/ttyd-proxy`.

### 2. Scrollen mit dem Mausrad in tmux

- `addon/rootfs/root/.tmux.conf`: `set -g mouse on` und `set -g history-limit 10000`.
- **Nachteil:** Normales Markieren mit der Maus geht nicht mehr, man braucht **Shift+Ziehen**. Ohne diesen Trick waren Textauswahl und das Kopieren der Login-URL kaputt (siehe `5f9cf41`).
- Im Endstand weist kein Hinweis die Nutzer auf Shift+Ziehen hin, weil `3543fe4` ihn wieder entfernt hat.

### 3. Nur für den Test

Dazu gehören Slug, Name, Beschreibung und Version in `addon/config.yaml` sowie der Eintrag in `addon/CHANGELOG.md`. **Nicht übernehmen.** Ein anderer Slug macht daraus ein separates Add-on mit eigenen Daten.

## Stand der Prüfung (08.10.2026)

- **Nicht getestet** gegen den aktuellen Fork 0.3.1. Der Dev-Slug und der Revert zeigen, dass damals auf einem Gerät getestet wurde. Ob der Endstand dort funktionierte, ist nicht dokumentiert.
- **Probe-Merge** gegen `main` (`6b4e1aa`): Konflikte gibt es nur in `addon/CHANGELOG.md` und `addon/config.yaml`, also in den Teilen, die man nicht will.
- `ttyd/run` und `claude-entrypoint.sh` sind im Fork noch identisch mit 0.1.11. Node.js ist im Laufzeit-Image enthalten, weil der MCP-Server es braucht.
- Die Persistenz im Fork verlinkt nur `/root/.claude`, `/root/.claude.json` und `/root/.bash_history` nach `/data`. Eine `/root/.tmux.conf` aus dem Image bleibt deshalb erhalten.

## In den Fork übernehmen (falls gewünscht)

Nicht alle Commits per Cherry-Pick übernehmen, sondern nur die funktionalen Dateien:

```bash
git fetch origin
git checkout -b feat/mobile-esc-button origin/main
git checkout origin/archive/0.1.12-esc-button-tmux-scroll -- \
  addon/rootfs/usr/bin/ttyd-proxy.js \
  addon/rootfs/etc/s6-overlay/s6-rc.d/ttyd-proxy \
  addon/rootfs/etc/s6-overlay/s6-rc.d/user/contents.d/ttyd-proxy \
  addon/rootfs/etc/s6-overlay/s6-rc.d/ttyd/run \
  addon/rootfs/root/.tmux.conf
```

Vorher prüfen, ob sich `ttyd/run` im Fork inzwischen geändert hat. Danach die Version erhöhen, den Changelog schreiben und den Hinweis auf Shift+Ziehen wieder einbauen.

Auf dem Gerät testen:

- Handy: Bricht der ESC-Button eine laufende Claude-Antwort ab?
- Desktop: Scrollt das Mausrad durch den Verlauf?
- Lässt sich Text mit Shift+Ziehen markieren und kopieren, auch die Login-URL?
- Verbindet sich das Terminal nach Tab-Wechsel oder Standby wieder (WebSocket über den Proxy)?
