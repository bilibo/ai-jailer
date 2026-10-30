#!/usr/bin/env bash
#   managed-tree-test.sh <managed tree>
#
# The managed tree (/etc/claude-code on a host): the law in
# managed-settings.json, which Claude Code reads for every user and so binds
# the jailer too (credential reads, `git commit`, `git push`, the hooks, the managed-only
# keys), the jail in jail-settings.json, the reference copy of a worker's
# rules that `aj bootstrap` writes into the worker's user settings and the
# hook checks them against (roadmap item 14, 2026-10-28), and the hooks.
# ai-jailer ships no mods since 2026-10-24, so the tree has no marketplace
# directory and the law registers no marketplace and enables no plugin; the
# keys that refuse every mod on a managed host are all there.
# shellcheck disable=SC2016  # the filters are jq
set -uo pipefail
[ $# -eq 1 ] || { echo "usage: managed-tree-test.sh <managed tree>" >&2; exit 64; }
t="$1"; s="$t/managed-settings.json"; j="$t/jail-settings.json"
pass=0; fail=0

ok() { # ok <description> <command...>
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $d"; fi
}

echo "== $t"
ok "law, jail and hooks present"                test -f "$s" -a -f "$j" -a -x "$t/hooks/env-guard.sh"
ok "nothing else in the tree"                   sh -c "[ \"\$(ls -A '$t' | tr '\n' ' ')\" = 'hooks jail-settings.json managed-settings.json ' ]"

# The law: what binds everyone, and nothing more.
ok "law: git push denied"                       jq -e '.permissions.deny | index("Bash(git push)") and index("Bash(git push *)")' "$s"
ok "law: git commit denied"                     jq -e '.permissions.deny | index("Bash(git commit)") and index("Bash(git commit *)")' "$s"
ok "law: own Claude login unreadable by rule"   jq -e '.permissions.deny | index("Read(~/.claude/.credentials.json)") != null' "$s"
ok "law: ssh keys and GitHub tokens unreadable" jq -e '.permissions.deny | index("Read(~/.ssh/**)") and index("Read(~/.config/gh/**)") and index("Read(~/.git-credentials)")' "$s"
ok "law: in-repo secrets unreadable"            jq -e '.permissions.deny | index("Read(**/.env)") and index("Read(**/*.tfvars)") and index("Read(**/*.tfstate)")' "$s"
ok "law: no other deny rule"                    jq -e '.permissions.deny | all(startswith("Read(") or startswith("Bash(git push") or startswith("Bash(git commit"))' "$s"
ok "law: .terraform readable (2026-10-29)"      jq -e '.permissions.deny | index("Read(**/.terraform/**)") == null' "$s"
ok "law: no sandbox"                            jq -e 'has("sandbox") | not' "$s"
ok "law: no account keys"                       jq -e '(has("syncClaudeAiSkills") or has("syncClaudeAiPlugins") or has("disableClaudeAiConnectors")) | not' "$s"
ok "law: bypass mode off"                       jq -e '.permissions.disableBypassPermissionsMode == "disable"' "$s"
ok "law: every hook is run by its /etc path"    jq -e '[.hooks[][].hooks[].command] | length > 0 and all(startswith("/etc/claude-code/hooks/"))' "$s"
ok "law: the guard on every writing tool"       jq -e '.hooks.PreToolUse[0].matcher == "Bash|Edit|Write|NotebookEdit" and .hooks.PreToolUse[0].hooks[0].onFailure == "block"' "$s"

# Mod policy (managed only, so the law's).
ok "no marketplace directory"                   test ! -e "$t/plugins"
ok "no marketplace registered"                  jq -e 'has("extraKnownMarketplaces") | not' "$s"
ok "no plugin enabled"                          jq -e 'has("enabledPlugins") | not' "$s"
ok "no prependPlugins (the guard loads on its own)" jq -e 'has("prependPlugins") | not' "$s"
ok "the guard refuses every mod"                jq -e '.pluginConfigs["cc-plugin-sec-default@builtin"].options.allowManagedModsOnly == true' "$s"
ok "no marketplace can be added"                jq -e '.strictKnownMarketplaces == []' "$s"
ok "sideload flags refused"                     jq -e '.disableSideloadFlags == true' "$s"
ok "only managed hooks run"                     jq -e '.allowManagedHooksOnly == true' "$s"

# The jail: a worker's full set, on the user.
ok "jail: sandbox on and mandatory"             jq -e '.sandbox.enabled == true and .sandbox.failIfUnavailable == true and .sandbox.allowUnsandboxedCommands == false' "$j"
ok "jail: no sealed network variant"            jq -e '.sandbox.network | has("strictAllowlist") | not' "$j"
ok "jail: unix sockets open (go-plugin, the daemon)" jq -e '.sandbox.network.allowAllUnixSockets == true' "$j"
ok "jail: git push and commit denied"           jq -e '.permissions.deny | index("Bash(git push)") and index("Bash(git commit)")' "$j"
ok "jail: nh os switch denied"                  jq -e '.permissions.deny | index("Bash(nh os switch)") != null' "$j"
ok "jail: .terraform readable (2026-10-29)"             jq -e '.permissions.deny | index("Read(**/.terraform/**)") == null' "$j"
ok "jail: no .devenv/.direnv Read deny (it would mask the store through the symlinks, 2026-10-29)" jq -e '.permissions.deny | map(select(test("^Read\\(.*\\.(devenv|direnv)"))) | length == 0' "$j"
ok "jail: the law's rules are in it too"        jq -e --slurpfile l "$s" '.permissions.deny as $d | all($l[0].permissions.deny[]; . as $r | $d | index($r) != null)' "$j"
ok "jail: cloud credentials are the sandbox's, not a Read rule" jq -e '.permissions.deny | index("Read(~/.aws/**)") == null' "$j"
ok "jail: credential paths hidden in the sandbox" jq -e '.sandbox.filesystem.denyRead | index("~/.ssh") and index("~/.claude/.credentials.json") and index("~/.config/gh")' "$j"
ok "jail: the aws directory is not in denyRead" jq -e '.sandbox.filesystem.denyRead | index("~/.aws") == null' "$j"
ok "jail: GitHub tokens stripped"               jq -e '[.sandbox.credentials.envVars[] | select(.mode == "deny") | .name] | index("GH_TOKEN") and index("GITHUB_TOKEN")' "$j"
ok "jail: claude.ai skills and plugins not synced" jq -e '.syncClaudeAiSkills == false and .syncClaudeAiPlugins == false' "$j"
ok "jail: account connectors off"               jq -e '.disableClaudeAiConnectors == true' "$j"
ok "jail: no hooks of its own (the law registers them)" jq -e 'has("hooks") | not' "$j"
ok "jail: no managed-only key"                  jq -e '(has("allowManagedHooksOnly") or has("strictKnownMarketplaces") or has("disableSideloadFlags") or has("pluginConfigs")) | not' "$j"

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
