#!/usr/bin/env bash
#   managed-tree-test.sh <managed tree with mods> <managed tree without> <mods source dir>
#
# The managed tree's mod wiring (docs/sessions.md section 5): with a mod, the
# managed settings register the marketplace directory by absolute path and
# enable the mod from it, the marketplace lists it by relative path, and the
# built plugin directory has the manifest the builder wrote plus a hooks
# module that exists; without one, nothing is registered. The checkout holds
# no manifest of its own.
set -uo pipefail
withmods="${1:?usage: managed-tree-test.sh <managed with mods> <managed without> <mods source dir>}"
plain="${2:?managed tree without mods}"
src="${3:?mods source dir}"
pass=0; fail=0

ok() { # ok <description> <command...>
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d"; fi
}

s="$withmods/managed-settings.json"
m="$withmods/plugins/.claude-plugin/marketplace.json"
p="$withmods/plugins/harness-broker"

ok "marketplace registered by absolute path"     jq -e '.extraKnownMarketplaces.harness.source == {source: "directory", path: "/etc/claude-code/plugins"}' "$s"
ok "broker enabled from it"                      jq -e '.enabledPlugins["harness-broker@harness"] == true' "$s"
ok "no prependPlugins (the guard loads on its own)" jq -e 'has("prependPlugins") | not' "$s"
ok "guard option and strict list unchanged"      jq -e '.pluginConfigs["cc-plugin-sec-default@builtin"].options.allowManagedModsOnly == true and .strictKnownMarketplaces[0] == {source: "directory", path: "/etc/claude-code/plugins"}' "$s"
ok "marketplace lists the mod by relative path"  jq -e '.name == "harness" and (.plugins | length == 1) and .plugins[0].name == "harness-broker" and .plugins[0].source == "./harness-broker"' "$m"
ok "manifest written by the builder"             jq -e '.name == "harness-broker" and (.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and (.description | length > 0)' "$p/.claude-plugin/plugin.json"
mod=$(jq -r '.modules[0]' "$p/hooks/hooks.json" 2>/dev/null)
ok "hooks.json names one module that exists"     test -n "$mod" -a -f "$p/hooks/$mod"
ok "the module exports register"                 grep -q 'export const register' "$p/hooks/$mod"
ok "types and tests travel with the mod"         sh -c "test -f '$p/types/index.d.ts' && ls '$p'/tests/*.test.ts"
ok "no manifest in the checkout"                 sh -c "! find '$src' -name .claude-plugin | grep -q ."

ok "plain tree registers nothing"                jq -e '(has("extraKnownMarketplaces") or has("enabledPlugins")) | not' "$plain/managed-settings.json"
ok "plain marketplace is empty"                  jq -e '.name == "harness" and .plugins == []' "$plain/plugins/.claude-plugin/marketplace.json"

echo "managed-tree-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
