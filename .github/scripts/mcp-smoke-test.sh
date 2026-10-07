#!/usr/bin/env bash
# Starts the MCP server in the built image and talks to it over stdio like
# Claude Code does: lists the tools and runs docs searches against the
# bundled index, which also exercises the native better-sqlite3 module. The
# second search has a dot, which FTS5 cannot parse, and the third a typo; both
# need the fallbacks in search.ts.
# Usage: mcp-smoke-test.sh <image>
set -euo pipefail
image=$1

out=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke-test","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search_docs","arguments":{"query":"config flow","limit":1}}}' \
  '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"search_docs","arguments":{"query":"light.turn_on","limit":1}}}' \
  '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"search_docs","arguments":{"query":"automaton trigger","limit":1}}}' \
  | timeout 120 docker run -i --rm -e SUPERVISOR_TOKEN=smoke-test \
      --entrypoint node "$image" /opt/mcp-server/dist/index.js)

tools=$(jq -r 'select(.id == 2) | .result.tools[].name' <<< "$out")
for tool in search_entities get_entity_state call_service search_automations get_ha_config \
            list_areas search_devices get_config_entries search_docs read_doc get_doc_stats; do
  if ! grep -qx "$tool" <<< "$tools"; then
    echo "::error::MCP server does not offer the tool $tool"
    exit 1
  fi
done

for id in 3 4 5; do
  hits=$(jq -r --argjson id "$id" 'select(.id == $id) | if .result.isError then "error" else (.result.content[0].text | fromjson | length) end' <<< "$out")
  if [ -z "$hits" ] || [ "$hits" = error ] || [ "$hits" -lt 1 ]; then
    echo "::error::Docs search in the MCP server returned no results (request $id)"
    jq -c --argjson id "$id" 'select(.id == $id)' <<< "$out"
    exit 1
  fi
done
if ! jq -e 'select(.id == 5) | .result.content[1].text | test("automation trigger")' <<< "$out" > /dev/null; then
  echo "::error::Docs search did not correct the typo in \"automaton trigger\""
  jq -c 'select(.id == 5)' <<< "$out"
  exit 1
fi
echo "MCP server OK: $(wc -l <<< "$tools") tools, docs search works (also with a dot and a typo)."
