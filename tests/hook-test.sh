#!/usr/bin/env bash
#   hook-test.sh <path-to-env-guard.sh>
#
# Feeds hook JSON on stdin, no Claude Code needed (0 = allow, 2 = block).
# Add a case per hard limit you rely on; a case that stops passing after a
# regex change is the point of this file.
set -uo pipefail
hook="${1:?usage: hook-test.sh <env-guard.sh>}"
# The roots come from the built hook; with none, everything is in scope and
# the out-of-scope section is skipped.
ROOTS=$(sed -n 's/^ENFORCEMENT_ROOTS="\(.*\)"$/\1/p' "$hook")
IN="${HOOK_TEST_IN:-${ROOTS%%:*}/acme/infra}"; IN="${IN/#\~/$HOME}"
OUT="${HOOK_TEST_OUT:-/tmp/p}"
pass=0; fail=0

run() { # run <expected-exit> <json>
  local want="$1" json="$2" got
  printf '%s' "$json" | "$hook" >/dev/null 2>&1; got=$?
  if [ "$got" = "$want" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL (want $want, got $got): $json"; fi
}
cwd="$IN"
bash_cmd() { printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' "$cwd" "$(printf '%s' "$1" | jq -Rs .)"; }
edit_file() { printf '{"hook_event_name":"PreToolUse","tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s"}}' "$cwd" "$1"; }
allow() { run 0 "$(bash_cmd "$1")"; }
block() { run 2 "$(bash_cmd "$1")"; }

# --- 1. git history -------------------------------------------------------
allow 'git status'
allow 'git add -A'
allow 'git diff --cached'
allow 'git log --oneline -20'
allow 'git switch -c feature/x'
allow 'git stash list'
allow 'git commitlint'              # prefix of a different word
block 'git commit -m "x"'
block 'git commit'
block 'git push origin main'
block "git 'push'"
block 'git -C . push'
block 'git -c user.name=x push'
block 'GIT_DIR=/tmp/x git push'
block 'bash -c "git commit -m x"'
block 'cd /tmp && git reset --hard HEAD~1'
block 'env FOO=1 git rebase -i main'
block 'git stash drop'
block 'git branch -D main'
block 'git update-ref refs/heads/main abc'
block 'git checkout -- .'
block 'git restore --staged .'
block 'timeout 10 git merge main'
block 'git push || true'
block 'echo hi; git push'
block 'direnv exec . git push'

# --- 2. cloud / infra -----------------------------------------------------
allow 'terraform plan -out tf.plan'
allow 'terraform validate'
allow 'terraform show'
allow 'az account show'
allow 'az group list -o table'
allow 'az storage account show -n x'
block 'terraform apply tf.plan'
block 'terraform -chdir=infra apply'
block 'terraform state rm module.x'
block 'tofu destroy -auto-approve'
block 'terragrunt apply'
block 'az group create -n x -l westeurope'
block 'az storage account update -n x --https-only true'
block 'az deployment group create -g x -f main.bicep'
block 'az rest --method put --url https://management.azure.com/x'
block 'az rest --url x --method DELETE'
block 'az vm start -n x'
block 'func azure functionapp publish myapp'
block 'pulumi up'

# --- 3. credentials -------------------------------------------------------
allow 'ls -la'
allow 'cat README.md'
allow 'grep -r "resource" modules/'
allow 'grep -rn token src/'
allow 'cat tokenizer.py'
allow 'ls scripts/powershell/'
allow 'cat notes.exe.md'
block 'az login'
block 'az login --use-device-code'
block 'az account set -s x'
block 'az account get-access-token'
block 'az keyvault secret show --vault-name v -n s'
block 'cat .env'
block 'cat ./.env.local'
block 'cat terraform.tfvars'
block 'head -c 100 terraform.tfstate'
block 'cat ~/.azure/msal_token_cache.json'
block 'cat ~/.ssh/id_ed25519'
block 'python3 -c "print(open(\".env\").read())"'
block 'source .env'
block 'grep -r token ~/.azure/'
block 'base64 .env'

# --- 4. system / config ---------------------------------------------------
allow 'nix build .#foo'
allow 'nix flake check'
allow 'nix develop -c true'
block 'sudo ls'
block 'echo x | sudo tee /etc/foo'
block 'nix profile install nixpkgs#hello'
block 'nix-env -iA nixpkgs.hello'
block 'nixos-rebuild switch'
block 'home-manager switch'
block 'systemctl restart foo'
block 'cmd.exe /c dir'
block '/mnt/c/Windows/System32/cmd.exe'
block 'powershell.exe -c Get-Date'
block 'pwsh -c 1'
block 'clip.exe'
block 'echo x > devenv.nix'
block 'echo x >> .envrc'
block 'tee devenv.local.nix < x'
block 'sed -i s/a/b/ devenv.yaml'
block 'cp evil.json .claude/settings.json'
block 'rm -rf .claude/'
block 'ln -s /tmp/x .git/hooks/pre-commit'
allow 'ls .claude/ 2>/dev/null'
allow 'cat devenv.nix'
allow 'git diff devenv.nix'

# --- 5. plugins / mods ----------------------------------------------------
allow 'claude --version'
allow 'claude -p "hello"'
block 'claude plugin install foo@bar'
block 'claude plugin marketplace add x'
block 'claude --plugin-dir ./evil -p hi'
block 'claude --plugin-url https://x -p hi'
block 'claude --mcp-config ./m.json -p hi'
block 'claude --agents ./a.json -p hi'
block 'CLAUDE_CODE_PLUGIN_DIRS=/tmp/x claude -p hi'

# --- Edit / Write tool ----------------------------------------------------
run 0 "$(edit_file $IN/main.tf)"
run 0 "$(edit_file $IN/README.md)"
run 2 "$(edit_file $IN/devenv.nix)"
run 2 "$(edit_file $IN/devenv.local.nix)"
run 2 "$(edit_file $IN/.envrc)"
run 2 "$(edit_file $IN/.env)"
run 2 "$(edit_file $IN/.env.local)"
run 2 "$(edit_file $IN/terraform.tfvars)"
run 2 "$(edit_file $IN/.claude/settings.json)"
run 2 "$(edit_file $IN/.claude/settings.local.json)"
run 2 "$(edit_file $IN/.claude/skills/x/SKILL.md)"
run 2 "$(edit_file $IN/.claude/skills/x/.claude-plugin/plugin.json)"
run 2 "$(edit_file "$HOME/.claude/settings.json")"
run 2 "$(edit_file "$HOME/.claude.json")"
run 2 "$(edit_file "$HOME/.bashrc")"
# Auto-memory lives under ~/.claude/projects/<slug>/memory/. Allowed only when
# the host was built with allowMemoryEdits; nothing else under ~/.claude ever.
MEM=$(sed -n 's/^ALLOW_MEMORY_EDITS="\(.*\)"$/\1/p' "$hook")
mem="$HOME/.claude/projects/-home-x-repo/memory"
if [ "$MEM" = 1 ]; then
  run 0 "$(edit_file "$mem/MEMORY.md")"
  run 0 "$(edit_file "$mem/some-fact.md")"
  run 0 "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"cwd\":\"$IN\",\"tool_input\":{\"file_path\":\"$mem/new.md\",\"content\":\"x\"}}"
else
  run 2 "$(edit_file "$mem/MEMORY.md")"
fi
run 2 "$(edit_file "$mem/../session.jsonl")"
run 2 "$(edit_file "$mem/../../../settings.json")"
run 2 "$(edit_file "$HOME/.claude/projects/-home-x-repo/session.jsonl")"
run 2 "$(edit_file "$HOME/.claude/projects/memory/x.md")"
run 2 "$(edit_file "$HOME/.claude/memory/x.md")"
run 2 "$(edit_file $IN/.git/hooks/pre-commit)"
run 2 "$(edit_file $IN/.git/config)"
run 2 "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"cwd\":\"$IN\",\"tool_input\":{\"file_path\":\"$IN/.claude/hooks/x.sh\",\"content\":\"x\"}}"
run 2 "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"NotebookEdit\",\"cwd\":\"$IN\",\"tool_input\":{\"notebook_path\":\"$IN/.envrc\"}}"

# --- Outside the enforcement roots: project rules off, universal rules on --
if [ -n "$ROOTS" ]; then
cwd="$OUT"
allow 'git commit -m "personal"'
allow 'git push origin main'
allow 'terraform apply'
allow 'echo x > devenv.nix'
allow 'az group create -n x'
run 0 "$(edit_file "$OUT/devenv.nix")"
run 0 "$(edit_file "$OUT/.envrc")"
run 0 "$(edit_file "$OUT/.claude/settings.json")"
block 'sudo ls'
block 'az login'
block 'cat .env'
block 'nixos-rebuild switch'
block 'claude --plugin-dir ./evil -p hi'
block 'cmd.exe /c dir'
run 2 "$(edit_file "$HOME/.claude/settings.json")"
run 2 "$(edit_file "$HOME/.bashrc")"
# A session outside the roots that reaches into a repo under them.
block "git -C $IN push"
block "cd $IN && terraform apply"
block "bash -c 'cd ~/code/git/acme/infra && git commit -m x'"
run 2 "$(edit_file "$IN/devenv.nix")"
run 2 "$(edit_file "$IN/.envrc")"
# Unknown cwd fails closed.
run 2 '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push"}}'
cwd="$IN"
fi

# --- ConfigChange ---------------------------------------------------------
run 2 '{"hook_event_name":"ConfigChange","source":"user_settings"}'
run 2 '{"hook_event_name":"ConfigChange","source":"policy_settings"}'
run 0 '{"hook_event_name":"ConfigChange","source":"project_settings"}'

# --- Session hooks: writes the env preamble -------------------------------
envfile=$(mktemp)
CLAUDE_ENV_FILE="$envfile" "$hook" <<<"{\"hook_event_name\":\"SessionStart\",\"cwd\":\"$IN\"}" >/dev/null 2>&1
if grep -q 'direnv export bash' "$envfile"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: SessionStart did not write CLAUDE_ENV_FILE"; fi
rm -f "$envfile"
# Other tools and events pass through.
run 0 "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Read\",\"cwd\":\"$IN\",\"tool_input\":{\"file_path\":\"$IN/.env\"}}"
run 0 '{"hook_event_name":"Stop"}'
# Garbage input must deny, not allow.
run 2 'not json at all'

echo "hook-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
