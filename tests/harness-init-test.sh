#!/usr/bin/env bash
#   harness-init-test.sh <path-to-harness>
#
# `harness init --dry-run` under a temp HOME and code root: it prints every
# file a new repo gets and creates nothing, not even the repo directory.
set -uo pipefail
harness="${1:?usage: harness-init-test.sh <harness>}"
pass=0; fail=0
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home"

check() { # check <description> <want-regex>
  if [[ "$out" =~ $2 ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (/$2/)"; printf '%s\n' "$out" | sed 's/^/  /'; fi
}
init() { # init <args...>: sets out and rc
  out=$(env -i HOME="$tmp/home" PATH=/var/empty HARNESS_CODE_ROOT="$tmp/code" "$harness" init "$@" 2>&1); rc=$?
}

init --dry-run acme/demo
if [ "$rc" = 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: init --dry-run exits $rc"; fi
check "the repo path"         "harness init: $tmp/code/acme/demo \\(project acme/demo\\)"
for f in devenv.yaml devenv.nix .envrc CLAUDE.md; do check "plans $f" "would write +$f"; done
check "plans .gitignore"       'would add +\.gitignore: \.claude/settings\.json'
check "plans .worktreeinclude" 'would add +\.worktreeinclude: \.claude/settings\.json'
check "no shell step"          'shell step skipped'
check "default ref is the published repo" 'harness: +github:bilibo/claude-nix-harness \(default\)'
refute_store_warning() { if [[ "$out" =~ 'would pin a store path' ]]; then fail=$((fail+1)); echo "FAIL: store-path warning on the default ref"; else pass=$((pass+1)); fi; }
refute_store_warning
if [ -z "$(find "$tmp" -mindepth 1 -not -path "$tmp/home")" ]; then pass=$((pass+1))
else fail=$((fail+1)); echo "FAIL: --dry-run created files:"; find "$tmp" -mindepth 1 -not -path "$tmp/home" | sed 's/^/  /'; fi

init --dry-run --harness github:bilibo/claude-nix-harness acme/demo
check "--harness names the ref" 'harness: +github:bilibo/claude-nix-harness \(--harness\)'
HARNESS_REF=path:/somewhere
out=$(env -i HOME="$tmp/home" PATH=/var/empty HARNESS_CODE_ROOT="$tmp/code" HARNESS_REF="$HARNESS_REF" "$harness" init --dry-run acme/demo 2>&1)
check "HARNESS_REF names the ref" 'harness: +path:/somewhere \(HARNESS_REF\)'
# Shared flags before the command land on it too.
out=$(env -i HOME="$tmp/home" PATH=/var/empty HARNESS_CODE_ROOT="$tmp/code" "$harness" --dry-run init acme/demo 2>&1)
check "--dry-run before the command" 'would write +devenv\.yaml'
if [ ! -e "$tmp/code" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $tmp/code was created"; fi

init
if [ "$rc" = 64 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: init without a target exits $rc, want 64"; fi
out=$("$harness" init --help 2>&1)
check "init --help" 'harness init <customer>/<repo>'
out=$("$harness" check --help 2>&1)
check "check --help" 'harness check \[<repo>\]'

echo "harness-init-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
