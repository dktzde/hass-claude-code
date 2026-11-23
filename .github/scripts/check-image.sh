#!/usr/bin/env bash
# Checks a test-built add-on image: the pinned Claude Code version is the one
# installed, Python with its modules and the extra command line tools run,
# ttyd's saved page has what the browser scripts need, and the MCP server
# answers (mcp-smoke-test.sh). Used by the weekly "Update add-on" for amd64
# and aarch64 and by "Test build" for pull requests. The image must match the
# runner's architecture (no emulation).
# Usage: check-image.sh <image>
set -euo pipefail
image=$1
script_dir=$(dirname "$0")

echo "Architecture: $(docker run --rm --entrypoint uname "$image" -m)"

pinned=$(grep -oP '^ARG CLAUDE_CODE_VERSION=\K.*' addon/Dockerfile)
installed=$(docker run --rm --entrypoint /root/.local/bin/claude "$image" --version | awk '{print $1}')
echo "Claude Code installed: $installed, pinned: $pinned"
if [ "$installed" != "$pinned" ]; then
  echo "::error::Claude Code $installed is installed, but $pinned is pinned"
  exit 1
fi

docker run --rm --entrypoint python3 "$image" -c 'import json, sqlite3, ssl, sys, yaml; print(sys.version, "PyYAML", yaml.__version__)'
docker run --rm --entrypoint sh "$image" -c 'command -v mosquitto_pub && command -v mosquitto_sub && gh --version'

# The browser scripts need ttyd's saved page with window.term, </head> and
# </body>; reconnect.js needs ttyd's WebSocket protocol "tty" and its /token
# endpoint (see MAINTENANCE.md)
docker run --rm --entrypoint sh "$image" -c 'cd /usr/share/ttyd-addon && grep -q "window.term=" ttyd-index.html && grep -q "</head>" ttyd-index.html && grep -q "</body>" ttyd-index.html && grep -qF "[\"tty\"]" ttyd-index.html && grep -qF "\"/token\"" ttyd-index.html && test -s reconnect.js && ls'

bash "$script_dir/mcp-smoke-test.sh" "$image"
