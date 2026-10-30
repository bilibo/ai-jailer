#!/usr/bin/env bash
#   project-settings-test.sh <settings.json> [fenced] [<repo-root>]
#
# The repo's .claude/settings.json as the devenv module writes it: the
# project layer only. The hard rules (deny list, hooks, credential lists,
# mod policy) are in the managed tree, checked by managed-tree-test.sh; this
# file carries a few scalars as a belt, literal denyWrite paths under the
# checkout, the project's extra domains and, when on, the read fence.
#
# `fenced`: the file was generated with `readFence = true`; the read fence
# checks replace the "no fence" check. `<repo-root>`: the path the file was
# generated for, where its literal entries point; default /repo, the flake
# fixtures' root. aj init passes the real repo.
#
# A `center` argument is still ignored, not an error: pkgs/aj/init.sh
# passes it until item C2 of the 2026-10-27 redesign removes the mode there.
# shellcheck disable=SC2016  # the filters are jq, where $repo is a jq variable
set -uo pipefail
f="${1:?usage: project-settings-test.sh <settings.json> [fenced] [<repo-root>]}"
mode=""; repo=/repo
for a in "${@:2}"; do case "$a" in fenced) mode="$a" ;; center) ;; *) repo="$a" ;; esac; done
pass=0; fail=0

check() { # check <description> <jq filter that must be true; $repo is the repo root>
  if jq -e --arg repo "$repo" "$2" "$f" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 ($2)"; fi
}

check "has a schema"                            'has("$schema")'
check "bypass mode disabled"                    '.permissions.disableBypassPermissionsMode == "disable"'
check "no deny rules by default"                '.permissions.deny == []'
check "no hooks (they are managed)"             'has("hooks") | not'
check "account connectors off"                  '.disableClaudeAiConnectors == true'
check "no co-author trailer"                    '.includeCoAuthoredBy == false'
# In user scope it turns the sandbox's Bash auto-allow off (2026-10-22); in
# a repo file it is ignored. Never written.
check "no subprocess scrub key"                 '.env.CLAUDE_CODE_SUBPROCESS_ENV_SCRUB == null'
check "no managed-only keys in a repo file"     '(has("allowManagedHooksOnly") or has("strictKnownMarketplaces") or has("disableSideloadFlags") or has("pluginConfigs") or has("syncClaudeAiSkills") or has("syncClaudeAiPlugins") or (.sandbox.network // {} | has("strictAllowlist"))) | not'
# The sandbox is the jail's (roadmap item 14): the worker's user settings
# turn it on, the repo file never writes the key (a false here would turn a
# worker's off, which the hook refuses); the two belt scalars stay.
check "sandbox key absent, never false"         '(.sandbox | has("enabled") | not) and .sandbox.failIfUnavailable == true and .sandbox.allowUnsandboxedCommands == false'
check "no credential list in the repo file"     '.sandbox | has("credentials") | not'
# Linux honours literal write entries only (lib/settings.nix): the repo's
# own files by absolute path, no glob.
check "denyWrite is the seven literal paths"    '.sandbox.filesystem.denyWrite == [$repo + "/.git/hooks", $repo + "/.git/config", $repo + "/.claude/settings.json", $repo + "/.claude/settings.local.json", $repo + "/.claude/hooks", $repo + "/.claude/skills", $repo + "/.claude-plugin"]'
check "no glob in denyWrite"                    '.sandbox.filesystem.denyWrite | any(contains("*")) | not'
# A literal entry is masked as an unreadable device node, and devenv reads
# devenv.local.* when they exist: with them listed, no shell evaluated inside
# the sandbox (2026-10-22). The hook refuses writes to them by name.
check "devenv.local.* readable by devenv"       '.sandbox.filesystem.denyWrite | (index($repo + "/devenv.local.nix") or index($repo + "/devenv.local.yaml")) | not'
check "no extra domains by default"             '.sandbox.network.allowedDomains == []'
check "no unix sockets opened"                  '.sandbox.network | has("allowAllUnixSockets") | not'
if [ "$mode" = fenced ]; then
  check "home hidden from the shell"            '.sandbox.filesystem.denyRead == ["~/"]'
  check "repo and shell entry paths readable"   '.sandbox.filesystem.allowRead | index($repo) and index("~/.cache/devenv") and index("~/.claude/shell-snapshots") and index("~/.cargo")'
  check "credentials stay hidden"               '.sandbox.filesystem.allowRead | index("~/.claude") or index("~/") | not'
else
  check "no read fence by default"              '.sandbox.filesystem | has("denyRead") | not'
  check "no allowRead without the fence"        '.sandbox.filesystem | has("allowRead") | not'
fi

echo "project-settings-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
