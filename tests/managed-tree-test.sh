#!/usr/bin/env bash
#   managed-tree-test.sh <managed tree>
#
# The managed tree (/etc/claude-code on a host): the hard rules that bind
# every user, and the mod policy (docs/sessions.md section 5). The harness
# ships no mods since 2026-10-24, so the tree has no marketplace directory
# and its settings register no marketplace and enable no plugin; the keys
# that refuse every mod on a managed host are all there.
# shellcheck disable=SC2016  # the filters are jq
set -uo pipefail
[ $# -eq 1 ] || { echo "usage: managed-tree-test.sh <managed tree>" >&2; exit 64; }
t="$1"; s="$t/managed-settings.json"
pass=0; fail=0

ok() { # ok <description> <command...>
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d"; fi
}

echo "== $t"
ok "settings and hooks present"                 test -f "$s" -a -x "$t/hooks/env-guard.sh"
ok "nothing but settings and hooks in the tree" sh -c "[ \"\$(ls -A '$t' | tr '\n' ' ')\" = 'hooks managed-settings.json ' ]"

# Mod policy.
ok "no marketplace directory"                   test ! -e "$t/plugins"
ok "no marketplace registered"                  jq -e 'has("extraKnownMarketplaces") | not' "$s"
ok "no plugin enabled"                          jq -e 'has("enabledPlugins") | not' "$s"
ok "no prependPlugins (the guard loads on its own)" jq -e 'has("prependPlugins") | not' "$s"
ok "the guard refuses every mod"                jq -e '.pluginConfigs["cc-plugin-sec-default@builtin"].options.allowManagedModsOnly == true' "$s"
ok "no marketplace can be added"                jq -e '.strictKnownMarketplaces == []' "$s"
ok "sideload flags refused"                     jq -e '.disableSideloadFlags == true' "$s"
ok "only managed hooks run"                     jq -e '.allowManagedHooksOnly == true' "$s"

# Host-wide rules.
ok "claude.ai skills not synced"                jq -e '.syncClaudeAiSkills == false' "$s"
ok "claude.ai plugins not synced"               jq -e '.syncClaudeAiPlugins == false' "$s"
ok "no sealed network variant"                  jq -e '.sandbox.network | has("strictAllowlist") | not' "$s"
ok "sandbox on"                                 jq -e '.sandbox.enabled == true' "$s"
ok "git push denied"                            jq -e '.permissions.deny | index("Bash(git push)") != null' "$s"
ok "cloud credentials are the sandbox's, not a Read rule" jq -e '.permissions.deny | index("Read(~/.aws/**)") == null' "$s"
ok "own Claude login unreadable by rule"        jq -e '.permissions.deny | index("Read(~/.claude/.credentials.json)") != null' "$s"
ok "credential paths hidden in the sandbox"     jq -e '.sandbox.filesystem.denyRead | index("~/.ssh") and index("~/.claude/.credentials.json") and index("~/.config/gh")' "$s"
ok "the aws directory is not in denyRead"                 jq -e '.sandbox.filesystem.denyRead | index("~/.aws") == null' "$s"
ok "every hook is run by its /etc path"         jq -e '[.hooks[][].hooks[].command] | length > 0 and all(startswith("/etc/claude-code/hooks/"))' "$s"

# Every hook file is executable and accepts an event it does not handle.
for h in "$t"/hooks/*; do
  if [ -x "$h" ] && printf '{"hook_event_name":"Stop"}' | "$h" >/dev/null 2>&1; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); echo "FAIL: hook not runnable: $h"
  fi
done

echo "managed-tree-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
