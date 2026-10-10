#!/usr/bin/env bash
# Starts the MCP server in the built image and talks to it over stdio like
# Claude Code does: lists the tools and runs docs searches against the
# bundled index, which also exercises the native better-sqlite3 module. The
# second search has a dot, which FTS5 cannot parse, and the third a typo; both
# need the fallbacks in search.ts.
#
# It also calls call_service, whose input schema zod checks. There is no Home
# Assistant here (and no network), so valid input must get as far as the HTTP
# request and fail there, while invalid input must fail with a validation
# error. Together they show that zod accepts and rejects correctly, which a
# zod major update can break without any compile error.
#
# list_areas goes over the websocket API. Without Home Assistant it must
# report an error; until 0.4.2 it returned an empty list on every error.
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
  '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"call_service","arguments":{"domain":"light","service":"turn_on","data":{"entity_id":"light.smoke_test","brightness":255}}}}' \
  '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"call_service","arguments":{"service":"turn_on"}}}' \
  '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"call_service","arguments":{"domain":"light","service":"turn_on","data":"not an object"}}}' \
  '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"list_areas","arguments":{}}}' \
  | timeout 120 docker run -i --rm --network none -e SUPERVISOR_TOKEN=smoke-test \
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

# The model sees this schema; "data" must stay an object, not a string or any
if ! jq -e 'select(.id == 2) | .result.tools[] | select(.name == "call_service") | .inputSchema
            | .properties.data.type == "object" and (.required | index("domain") and index("service"))' \
     <<< "$out" > /dev/null; then
  echo "::error::tools/list no longer describes call_service as domain and service (required) plus a data object"
  jq -c 'select(.id == 2) | .result.tools[] | select(.name == "call_service") | .inputSchema' <<< "$out"
  exit 1
fi

# error_of ID: the error text of a reply, empty if it succeeded. The SDK reports
# a failed tool call as a result with isError, older versions as a JSON-RPC error.
error_of() {
  jq -r --argjson id "$1" 'select(.id == $id)
    | .error.message // (if .result.isError then .result.content[0].text else empty end) // empty' <<< "$out"
}
reply_of() { jq -c --argjson id "$1" 'select(.id == $id)' <<< "$out"; }

valid=$(error_of 6)
if [ -z "$(reply_of 6)" ] || [ -z "$valid" ] || grep -qi validation <<< "$valid"; then
  echo "::error::call_service with valid input must fail at the HTTP request (there is no Home Assistant), not at validation"
  reply_of 6
  exit 1
fi
for id in 7 8; do
  if ! grep -qi validation <<< "$(error_of "$id")"; then
    echo "::error::call_service with invalid input (request $id) must fail with a validation error"
    reply_of "$id"
    exit 1
  fi
done

if ! grep -q "websocket command config/area_registry/list failed" <<< "$(error_of 9)"; then
  echo "::error::list_areas without Home Assistant must fail at the websocket connection, not return a list"
  reply_of 9
  exit 1
fi

echo "MCP server OK: $(wc -l <<< "$tools") tools, docs search works (also with a dot and a typo), call_service input is validated, websocket errors are reported."
