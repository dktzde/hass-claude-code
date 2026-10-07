#!/usr/bin/env bash
# Starts the MCP server in the built image and talks to it over stdio like
# Claude Code does: lists the tools and runs one docs search against the
# bundled index, which also exercises the native better-sqlite3 module.
# Usage: mcp-smoke-test.sh <image>
set -euo pipefail
image=$1

out=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke-test","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search_docs","arguments":{"query":"config flow","limit":1}}}' \
  | timeout 120 docker run -i --rm -e SUPERVISOR_TOKEN=smoke-test -e ENABLE_EMBEDDINGS=false \
      --entrypoint node "$image" /opt/mcp-server/dist/index.js)

tools=$(jq -r 'select(.id == 2) | .result.tools[].name' <<< "$out")
for tool in search_entities get_entity_state call_service search_automations get_ha_config \
            list_areas search_devices get_config_entries search_docs read_doc get_doc_stats; do
  if ! grep -qx "$tool" <<< "$tools"; then
    echo "::error::MCP server does not offer the tool $tool"
    exit 1
  fi
done

hits=$(jq -r 'select(.id == 3) | if .result.isError then "error" else (.result.content[0].text | fromjson | length) end' <<< "$out")
if [ -z "$hits" ] || [ "$hits" = error ] || [ "$hits" -lt 1 ]; then
  echo "::error::Docs search in the MCP server returned no results"
  jq -c 'select(.id == 3)' <<< "$out"
  exit 1
fi
echo "MCP server OK: $(wc -l <<< "$tools") tools, docs search works."
