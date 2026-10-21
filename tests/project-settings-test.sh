#!/usr/bin/env bash
#   project-settings-test.sh <settings.json> [fenced]
#
# `fenced`: the file was generated with `readFence = true`; the read fence
# checks replace the default's "no fence" check.
#
# The repo's .claude/settings.json as the devenv module writes it. On a host
# without managed settings this file is the whole harness, so every layer it
# is supposed to carry is asserted here, and every hook it names must run.
set -uo pipefail
f="${1:?usage: project-settings-test.sh <settings.json> [fenced]}"
fenced="${2:-}"
pass=0; fail=0

check() { # check <description> <jq filter that must be true>
  if jq -e "$2" "$f" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 ($2)"; fi
}

check "full deny set, not the universal subset" '.permissions.deny | index("Bash(git commit)") and index("Bash(terraform apply)") and index("Bash(sudo)")'
check "bypass mode disabled"                    '.permissions.disableBypassPermissionsMode == "disable"'
check "guard registered on every writing tool"  '.hooks.PreToolUse[0].matcher == "Bash|Edit|Write|NotebookEdit"'
check "guard failure blocks"                    '.hooks.PreToolUse[0].hooks[0].onFailure == "block"'
check "settings changes guarded"                '.hooks.ConfigChange[0].matcher | test("user_settings") and test("local_settings")'
check "env preamble hooks present"              '.hooks | has("SessionStart") and has("CwdChanged") and has("FileChanged")'
check "sandbox on and mandatory"                '.sandbox.enabled == true and .sandbox.failIfUnavailable == true and .sandbox.allowUnsandboxedCommands == false'
check "ssh key files hidden"                    '.sandbox.filesystem.denyRead | index("~/.ssh")'
check "agent socket stripped"                   '[.sandbox.credentials.envVars[] | select(.name == "SSH_AUTH_SOCK" and .mode == "deny")] | length == 1'
# The `**/` entries are asserted for presence only: Linux skips glob write
# entries (lib/settings.nix); `~/.claude` is the one that holds there.
check "own settings not writable from the shell" '.sandbox.filesystem.denyWrite | index("**/.claude/settings.json") and index("**/.claude/settings.local.json") and index("~/.claude")'
check "account connectors off"                  '.disableClaudeAiConnectors == true'
check "no co-author trailer"                    '.includeCoAuthoredBy == false'
# Linux honours literal write entries only: the repo's own files by absolute path.
check "own files denied by literal path"        '.sandbox.filesystem.denyWrite | index("/repo/.claude/settings.json") and index("/repo/.claude/settings.local.json") and index("/repo/.git/hooks") and index("/repo/.git/config") and index("/repo/.claude-plugin") and index("/repo/devenv.local.nix")'
check "subprocess environment scrubbed"         '.env.CLAUDE_CODE_SUBPROCESS_ENV_SCRUB == "1"'
if [ "$fenced" = fenced ]; then
  check "home hidden from the shell"            '.sandbox.filesystem.denyRead | index("~/")'
  check "repo and shell entry paths readable"   '.sandbox.filesystem.allowRead | index("/repo") and index("~/.nix-profile") and index("~/.local/share/direnv") and index("~/.claude/shell-snapshots") and index("~/.cargo")'
  check "credentials stay hidden"               '.sandbox.filesystem.allowRead | index("~/.claude") or index("~/") | not'
else
  check "no read fence by default"              '.sandbox.filesystem.denyRead | index("~/") | not'
  check "no allowRead without the fence"        '.sandbox.filesystem | has("allowRead") | not'
fi
check "no github token inside the sandbox"      '[.sandbox.credentials.envVars[] | select(.mode == "deny") | .name] | index("GITHUB_TOKEN") and index("GH_TOKEN")'
check "worktrees stay writable"                 '.sandbox.filesystem.denyWrite | index("**/.claude") | not'
check "no managed-only keys in a repo file"     '(has("allowManagedHooksOnly") or has("strictKnownMarketplaces") or has("disableSideloadFlags") or has("pluginConfigs") or (.sandbox.network | has("strictAllowlist"))) | not'

# Every hook the file names is a store path that exists, is executable and
# accepts an event it does not handle.
while read -r h; do
  if [ -x "$h" ] && printf '{"hook_event_name":"Stop"}' | "$h" >/dev/null 2>&1; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); echo "FAIL: hook not runnable: $h"
  fi
done < <(jq -r '[.hooks[][].hooks[].command] | unique[]' "$f")

echo "project-settings-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
