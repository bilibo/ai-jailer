#!/usr/bin/env bash
#   harness-init-test.sh <path-to-harness> [<settings.json>]
#
# `harness init --dry-run` under a temp HOME and code root: it prints every
# file a new repo gets and creates nothing, not even the repo directory. On
# an existing repo with its own devenv.nix, the shell step stops for approval;
# with --yes it reaches the checks, where the stub direnv has linked
# <settings.json> (a store path; default: the harness itself) as the repo's
# .claude/settings.json, and the settings test must get the repo's own path.
# A repo's own devenv.lock is shown as the inputs it pins and stops the same.
set -uo pipefail
harness="${1:?usage: harness-init-test.sh <harness> [<settings.json>]}"
settings="${2:-$harness}"
pass=0; fail=0
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home"

check() { # check <description> <want-regex>
  if [[ "$out" =~ $2 ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (/$2/)"; printf '%s\n' "$out" | sed 's/^/  /'; fi
}
init() { # init <args...>: sets out and rc
  out=$(env -i HOME="$tmp/home" PATH=/var/empty HARNESS_CODE_ROOT="$tmp/code" HARNESS_WSL_MARKER="${WSL_MARKER:-/var/empty/none}" "$harness" init "$@" 2>&1); rc=$?
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

# An existing repo with its own devenv.nix: the shell step prints it and,
# without --yes or a terminal, stops before any `direnv allow`. direnv and
# devenv are stubs that log their calls.
mkdir -p "$tmp/bin" "$tmp/foreign"; echo '{ pkgs, ... }: { enterShell = "foreign code"; }' >"$tmp/foreign/devenv.nix"
printf '#!/bin/sh\necho "direnv $*" >>"$CALLS"\n[ "$1" = version ] && echo 2.38.2\n[ "$1" = allow ] && [ -n "${2:-}" ] && mkdir -p "$2/.claude" && ln -sfn "$SETTINGS" "$2/.claude/settings.json"\nexit 0\n' >"$tmp/bin/direnv"
printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/devenv"; chmod +x "$tmp/bin/direnv" "$tmp/bin/devenv"
shell_init() { # shell_init <args...>: init on $repo_dir (default: the foreign repo) with the stubs, no terminal; sets out and rc
  : >"$tmp/calls"
  out=$(env -i HOME="$tmp/home" PATH="$tmp/bin" CALLS="$tmp/calls" SETTINGS="$settings" HARNESS_CODE_ROOT="$tmp/code" "$harness" init "$@" "${repo_dir:-$tmp/foreign}" 2>&1 </dev/null); rc=$?
}
shell_init
if [ "$rc" != 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: a foreign devenv.nix without --yes exits 0"; fi
check "the foreign file printed" 'foreign/devenv\.nix \(not written by harness init\).*foreign code'
check "refused, --yes named"     'not approved: devenv\.nix; .*re-run with --yes'
if grep -q 'direnv allow' "$tmp/calls"; then fail=$((fail+1)); echo "FAIL: direnv allow ran without approval"; else pass=$((pass+1)); fi
shell_init --yes --verbose
if grep -q "^direnv allow $tmp/foreign\$" "$tmp/calls"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: --yes did not reach direnv allow: $(tr '\n' ';' <"$tmp/calls")"; fi
# The repo is not at /repo, the fixtures' root: the settings test gets the
# repo's path (the --verbose trace shows the call), so its literal-path
# checks are the only ones that can fail against the /repo fixture.
check "settings test gets the repo path" "project-settings-test\.sh $tmp/foreign/\.claude/settings\.json $tmp/foreign[[:space:]]"
check "settings linked from the store"   'ok +\.claude/settings\.json -> /nix/store/'
if [[ "$out" =~ 'FAIL: full deny set' ]]; then fail=$((fail+1)); echo "FAIL: the settings test did not read the linked file"; else pass=$((pass+1)); fi

# A repo with its own devenv.lock and nothing else foreign: the inputs it
# pins are printed, and without --yes no `direnv allow` runs.
mkdir -p "$tmp/locked"
echo '{"nodes":{"nixpkgs":{"locked":{"type":"github","owner":"NixOS","repo":"nixpkgs","rev":"0123abc"}},"root":{"inputs":{"nixpkgs":"nixpkgs"}}},"root":"root","version":7}' >"$tmp/locked/devenv.lock"
repo_dir="$tmp/locked" shell_init
if [ "$rc" != 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: a foreign devenv.lock without --yes exits 0"; fi
check "the lock's inputs printed" 'locked/devenv\.lock \(not written by harness init\).*nixpkgs: github:NixOS/nixpkgs @ 0123abc'
check "the lock refused"          'not approved: devenv\.lock;'
if grep -q 'direnv allow' "$tmp/calls"; then fail=$((fail+1)); echo "FAIL: direnv allow ran with an unapproved lock"; else pass=$((pass+1)); fi

# A WSL host (fake marker): the dry run says so, and a real write (no shell
# step) puts harness.platform = "wsl" into devenv.nix; elsewhere the line
# stays commented out.
touch "$tmp/wsl"
WSL_MARKER="$tmp/wsl" init --dry-run acme/demo
check "wsl noted in the dry run" 'platform +wsl \(harness\.platform in devenv\.nix\)'
WSL_MARKER="$tmp/wsl" init --no-shell acme/wsl
if grep -q -E '^    platform = "wsl";' "$tmp/code/acme/wsl/devenv.nix"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: harness.platform not set on a WSL host"; fi
init --no-shell acme/plain
if grep -q -E '^    # platform = "wsl";' "$tmp/code/acme/plain/devenv.nix"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: platform line not commented out off WSL"; fi
if [[ "$out" =~ 'platform   wsl' ]]; then fail=$((fail+1)); echo "FAIL: wsl noted off WSL"; else pass=$((pass+1)); fi

echo "harness-init-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
