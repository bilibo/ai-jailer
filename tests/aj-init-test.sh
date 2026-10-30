#!/usr/bin/env bash
#   aj-init-test.sh <path-to-aj> [<settings.json>]
#
# `aj init --dry-run` under a temp HOME and code root: it prints every
# file a new repo gets and creates nothing, not even the repo directory. On
# an existing repo with its own devenv.nix, the shell step stops for approval;
# with --yes it reaches the checks, where the stub direnv has linked
# <settings.json> (a store path; default: aj itself) as the repo's
# .claude/settings.json, and the settings test must get the repo's own path.
# A repo's own devenv.lock is shown as the inputs it pins and stops the same.
# A repo with the guard rails off (ai-jail.enable = false) gets no settings
# file; init reports it and exits 0 without the checks. The hook test runs on
# the hook in the managed settings (AI_JAILER_MANAGED_SETTINGS, a fixture
# here); with no such file init prints MISSING, runs the settings test and
# exits 1. The generated devenv.nix carries no role, memory or local-commit
# text; CLAUDE.md carries the contract's action rules (proposals path, revert
# line). .gitignore gains proposals/ and .ignore devenv.lock (Grep skips it).
# With no claude on the host PATH (the default here: PATH is empty) the
# template turns ai-jail.claudeCode.enable on and devenv.yaml gets
# allow_unfree: true; with one, both stay commented out. A claude in a store
# directory (a shell's) or under ~/.vscode-server (the extension's) is not
# the host's. The template's .envrc fails while a devenv.local.* exists, and
# init stops on one unless the repo keeps its own .envrc.
set -uo pipefail
aj="${1:?usage: aj-init-test.sh <aj> [<settings.json>]}"
settings="${2:-$aj}"
pass=0; fail=0
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home"

check() { # check <description> <want-regex>
  if [[ "$out" =~ $2 ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (/$2/)"; printf '%s\n' "$out" | sed 's/^/  /'; fi
}
# has/lacks <description> <file> <regex>: a line in the file.
has()   { if grep -q -E "$3" "$2" 2>/dev/null; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (/$3/ in $2)"; sed 's/^/  /' "$2" 2>/dev/null; fi; }
lacks() { if grep -q -E "$3" "$2" 2>/dev/null; then fail=$((fail+1)); echo "FAIL: $1 (/$3/ in $2)"; sed 's/^/  /' "$2"; else pass=$((pass+1)); fi; }
init() { # init <args...>: sets out and rc; $HOST_PATH is the host's PATH (default: nothing), $STORE its NIX_STORE_DIR
  out=$(env -i HOME="$tmp/home" PATH="${HOST_PATH:-/var/empty}" ${STORE:+"NIX_STORE_DIR=$STORE"} AI_JAILER_CODE_ROOT="$tmp/code" AI_JAILER_WSL_MARKER="${WSL_MARKER:-/var/empty/none}" "$aj" init "$@" 2>&1); rc=$?
}

init --dry-run acme/demo
if [ "$rc" = 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: init --dry-run exits $rc"; fi
check "the repo path"         "aj init: $tmp/code/acme/demo \\(project acme/demo\\)"
for f in devenv.yaml devenv.nix .envrc CLAUDE.md; do check "plans $f" "would write +$f"; done
check "plans .gitignore"       'would add +\.gitignore: \.claude/settings\.json'
check "plans .gitignore proposals/" 'would add +\.gitignore: proposals/'
check "plans .ignore"          'would add +\.ignore: devenv\.lock'
check "plans .worktreeinclude" 'would add +\.worktreeinclude: \.claude/settings\.json'
check "no shell step"          'shell step skipped'
check "default ref is the published repo" 'jailer: +github:bilibo/ai-jailer \(default\)'
refute_store_warning() { if [[ "$out" =~ 'would pin a store path' ]]; then fail=$((fail+1)); echo "FAIL: store-path warning on the default ref"; else pass=$((pass+1)); fi; }
refute_store_warning
if [ -z "$(find "$tmp" -mindepth 1 -not -path "$tmp/home")" ]; then pass=$((pass+1))
else fail=$((fail+1)); echo "FAIL: --dry-run created files:"; find "$tmp" -mindepth 1 -not -path "$tmp/home" | sed 's/^/  /'; fi

init --dry-run --jailer github:bilibo/ai-jailer acme/demo
check "--jailer names the ref" 'jailer: +github:bilibo/ai-jailer \(--jailer\)'
AI_JAILER_REF=path:/somewhere
out=$(env -i HOME="$tmp/home" PATH=/var/empty AI_JAILER_CODE_ROOT="$tmp/code" AI_JAILER_REF="$AI_JAILER_REF" "$aj" init --dry-run acme/demo 2>&1)
check "AI_JAILER_REF names the ref" 'jailer: +path:/somewhere \(AI_JAILER_REF\)'
# Shared flags before the command land on it too.
out=$(env -i HOME="$tmp/home" PATH=/var/empty AI_JAILER_CODE_ROOT="$tmp/code" "$aj" --dry-run init acme/demo 2>&1)
check "--dry-run before the command" 'would write +devenv\.yaml'
if [ ! -e "$tmp/code" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $tmp/code was created"; fi

init
if [ "$rc" = 64 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: init without a target exits $rc, want 64"; fi
out=$("$aj" init --help 2>&1)
check "init --help" 'aj init <org>/<repo>'
out=$("$aj" check --help 2>&1)
check "check --help" 'aj check \[<repo>\]'

# An existing repo with its own devenv.nix: the shell step prints it and,
# without --yes or a terminal, stops before any `direnv allow`. direnv and
# devenv are stubs that log their calls. The direnv stub's `allow` links
# $SETTINGS (none when empty: a repo with the guard rails off), and its
# `exec` runs a command given by absolute path in the caller's environment.
mkdir -p "$tmp/bin" "$tmp/foreign"; echo '{ pkgs, ... }: { enterShell = "foreign code"; }' >"$tmp/foreign/devenv.nix"
printf '#!/bin/sh\necho "direnv $*" >>"$CALLS"\n[ "$1" = version ] && echo 2.38.2\n[ "$1" = allow ] && [ -n "${2:-}" ] && [ -n "$SETTINGS" ] && mkdir -p "$2/.claude" && ln -sfn "$SETTINGS" "$2/.claude/settings.json"\n[ "$1" = exec ] && case "$3" in /*) shift 2; exec "$@" ;; esac\nexit 0\n' >"$tmp/bin/direnv"
printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/devenv"; chmod +x "$tmp/bin/direnv" "$tmp/bin/devenv"
# A stub `bash` (init runs the unit tests with the PATH's bash, which this
# PATH lacks) that succeeds: the --verbose trace shows the calls. The
# managed settings fixture names the hook init should test.
printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/bash"; chmod +x "$tmp/bin/bash"
echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/etc/claude-code/hooks/env-guard.sh"}]}]}}' >"$tmp/managed.json"
shell_init() { # shell_init <args...>: init on $repo_dir (default: the foreign repo) with the stubs, no terminal, $MANAGED as the managed settings file (default: the fixture); sets out and rc
  : >"$tmp/calls"
  out=$(env -i HOME="$tmp/home" PATH="$tmp/bin" CALLS="$tmp/calls" SETTINGS="$settings" AI_JAILER_CODE_ROOT="$tmp/code" AI_JAILER_MANAGED_SETTINGS="${MANAGED:-$tmp/managed.json}" "$aj" init "$@" "${repo_dir:-$tmp/foreign}" 2>&1 </dev/null); rc=$?
}
shell_init
if [ "$rc" != 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: a foreign devenv.nix without --yes exits 0"; fi
check "the foreign file printed" 'foreign/devenv\.nix \(not written by aj init\).*foreign code'
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
# The repo file registers no hook: the unit test runs on the hook in the
# host's managed settings. A fixture file names a stub hook path; the stub
# `bash` succeeds, so the --verbose trace shows what init would run.
check "managed: settings test still gets the repo path" "bash .*project-settings-test\\.sh $tmp/foreign/\\.claude/settings\\.json $tmp/foreign[[:space:]]"
check "managed: hook test runs on the managed hook"     "bash .*hook-test\\.sh /etc/claude-code/hooks/env-guard\\.sh[[:space:]]"
check "managed: ready"                                   'Ready\.'
if [[ "$out" =~ 'MISSING' ]]; then fail=$((fail+1)); echo "FAIL: MISSING with a readable managed file"; else pass=$((pass+1)); fi
if [[ "$out" =~ AI_JAILER_ROLE|role\ +(work|center) ]]; then fail=$((fail+1)); echo "FAIL: init still mentions a role"; else pass=$((pass+1)); fi
# Without a managed file: MISSING, the settings test still runs, then exit 1
# before the hook test and the footer.
MANAGED="$tmp/none.json" shell_init --yes --verbose
if [ "$rc" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: no managed file exits $rc, want 1"; fi
check "missing: MISSING and the path"      "MISSING +no managed settings at $tmp/none\\.json: this host enforces nothing"
check "missing: settings test still ran"   "bash .*project-settings-test\\.sh "
if [[ "$out" =~ hook-test|Ready\. ]]; then fail=$((fail+1)); echo "FAIL: hook test or footer after MISSING"; else pass=$((pass+1)); fi

# A repo with its own devenv.lock and nothing else foreign: the inputs it
# pins are printed, and without --yes no `direnv allow` runs.
mkdir -p "$tmp/locked"
echo '{"nodes":{"nixpkgs":{"locked":{"type":"github","owner":"NixOS","repo":"nixpkgs","rev":"0123abc"}},"root":{"inputs":{"nixpkgs":"nixpkgs"}}},"root":"root","version":7}' >"$tmp/locked/devenv.lock"
repo_dir="$tmp/locked" shell_init
if [ "$rc" != 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: a foreign devenv.lock without --yes exits 0"; fi
check "the lock's inputs printed" 'locked/devenv\.lock \(not written by aj init\).*nixpkgs: github:NixOS/nixpkgs @ 0123abc'
check "the lock refused"          'not approved: devenv\.lock;'
if grep -q 'direnv allow' "$tmp/calls"; then fail=$((fail+1)); echo "FAIL: direnv allow ran with an unapproved lock"; else pass=$((pass+1)); fi

# A repo whose owner turned the guard rails off (ai-jail.enable = false):
# the shell loads (DEVENV_ROOT) without the jail module (no AI_JAIL_PROJECT) and
# devenv writes no settings file. init says so and exits 0 without the
# checks; a shell that did not load at all still fails as before.
mkdir -p "$tmp/off"; echo '{ ... }: { ai-jail.enable = false; }' >"$tmp/off/devenv.nix"
off_init() { # off_init [<VAR=value>...]: init --yes on the off repo, nothing linked; sets out and rc
  : >"$tmp/calls"
  out=$(env -i HOME="$tmp/home" PATH="$tmp/bin" CALLS="$tmp/calls" SETTINGS= AI_JAILER_CODE_ROOT="$tmp/code" "$@" "$aj" init --yes --verbose "$tmp/off" 2>&1 </dev/null); rc=$?
}
off_init DEVENV_ROOT="$tmp/off"
if [ "$rc" = 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: a repo with the guard rails off exits $rc"; printf '%s\n' "$out" | sed 's/^/  /'; fi
check "guard rails off reported" 'off +the shell loads without the guard rails: ai-jail\.enable = false in devenv\.nix'
if [ -e "$tmp/off/.claude/settings.json" ] || [ -L "$tmp/off/.claude/settings.json" ]; then fail=$((fail+1)); echo "FAIL: a settings file in the repo with the guard rails off"; else pass=$((pass+1)); fi
if [[ "$out" =~ project-settings-test|hook-test|Ready\. ]]; then fail=$((fail+1)); echo "FAIL: the checks ran with the guard rails off"; else pass=$((pass+1)); fi
off_init
if [ "$rc" != 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: a shell that did not load exits 0"; fi
check "not loaded is still an error" 'settings\.json was not written: the devenv shell did not load'

# A WSL host (fake marker): the dry run says so, and a real write (no shell
# step) puts ai-jail.platform = "wsl" into devenv.nix; elsewhere the line
# stays commented out.
touch "$tmp/wsl"
WSL_MARKER="$tmp/wsl" init --dry-run acme/demo
check "wsl noted in the dry run" 'platform +wsl \(ai-jail\.platform in devenv\.nix\)'
WSL_MARKER="$tmp/wsl" init --no-shell acme/wsl
if grep -q -E '^    platform = "wsl";' "$tmp/code/acme/wsl/devenv.nix"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: ai-jail.platform not set on a WSL host"; fi
init --no-shell acme/plain
if grep -q -E '^    # platform = "wsl";' "$tmp/code/acme/plain/devenv.nix"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: platform line not commented out off WSL"; fi
if [[ "$out" =~ 'platform   wsl' ]]; then fail=$((fail+1)); echo "FAIL: wsl noted off WSL"; else pass=$((pass+1)); fi
# The off switch is in the template, commented out, first in the ai-jailer block.
if grep -A1 -x -F '  ai-jail = {' "$tmp/code/acme/plain/devenv.nix" | grep -q -E '^    # enable = false; +# guard rails off'; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: no commented-out enable = false in the template's ai-jail block"; fi
# Host decisions, no longer project options: no role, memory or local-commit
# line in the template, not even commented out.
lacks "template: no role line"             "$tmp/code/acme/plain/devenv.nix" 'role'
lacks "template: no allowMemoryEdits"      "$tmp/code/acme/plain/devenv.nix" 'allowMemoryEdits'
lacks "template: no allowLocalCommits"     "$tmp/code/acme/plain/devenv.nix" 'allowLocalCommits'
has   "template: extraAllowedDomains note" "$tmp/code/acme/plain/devenv.nix" 'project hosts, merged into the sandbox allowlist \(live check V2, 2026-10-29\); \[ \"\*\" \] opens the network'
has   "CLAUDE.md: the contract heading"    "$tmp/code/acme/plain/CLAUDE.md" '^## Environment contract \(ai-jailer\)$'
has   "CLAUDE.md: devenv.nix read first"   "$tmp/code/acme/plain/CLAUDE.md" 'devenv\.nix.: read it first'
has   "CLAUDE.md: the proposals path"      "$tmp/code/acme/plain/CLAUDE.md" 'proposals/<YYYY-MM-DD>-<topic>\.patch'
has   "CLAUDE.md: the revert line"         "$tmp/code/acme/plain/CLAUDE.md" 'git show HEAD:<f> > <f>'
has   "CLAUDE.md: az scoped"               "$tmp/code/acme/plain/CLAUDE.md" 'never unfiltered JSON'
has   "the real run: .gitignore proposals/" "$tmp/code/acme/plain/.gitignore" '^proposals/$'
has   "the real run: .ignore devenv.lock"  "$tmp/code/acme/plain/.ignore" '^devenv\.lock$'

# The template's .envrc fails the load while devenv.local.nix or
# devenv.local.yaml exists (roadmap 2.7), before `use devenv`, with an error
# line the hook's preamble shows (the first stderr line matching "error").
# No direnv in the build: bash sources the generated file with direnv's
# functions stubbed, `use` echoing its arguments.
envrc_run() { # envrc_run <dir>: sets out and rc
  out=$(cd "$1" && "$BASH" -c 'devenv() { :; }; use() { echo "use $*"; }; require_allowed() { :; }; source ./.envrc' 2>&1); rc=$?
}
plain="$tmp/code/acme/plain"
envrc_run "$plain"
if [ "$rc" = 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: the template .envrc without devenv.local.* exits $rc"; printf '%s\n' "$out" | sed 's/^/  /'; fi
check "envrc: no devenv.local.*, reaches use devenv" '^use devenv$'
for f in devenv.local.yaml devenv.local.nix; do
  echo '{ }' >"$plain/$f"
  envrc_run "$plain"
  if [ "$rc" != 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: the template .envrc with $f exits 0"; fi
  if [[ "$(grep -i -m1 error <<<"$out")" == "error: $f is refused in a jail (devenv loads it without a direnv allow): remove it and direnv reload, or move its content into devenv.nix as a proposed diff" ]]; then pass=$((pass+1))
  else fail=$((fail+1)); echo "FAIL: the hook's error line for $f"; printf '%s\n' "$out" | sed 's/^/  /'; fi
  if [[ "$out" == *'use devenv'* ]]; then fail=$((fail+1)); echo "FAIL: use devenv ran with $f present"; else pass=$((pass+1)); fi
  rm -f "$plain/$f"
done
# The shell step: with the template's .envrc a devenv.local.* stops it before
# any `direnv allow`; with the repo's own .envrc it is approved like the rest.
mkdir -p "$tmp/local"; echo '{ }' >"$tmp/local/devenv.local.nix"
repo_dir="$tmp/local" shell_init --yes
if [ "$rc" != 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: devenv.local.nix with the template .envrc exits 0"; fi
check "local: refused, what to do named" 'devenv\.local\.nix exists and the \.envrc refuses to load with it .*: remove it, or move its content into devenv\.nix'
if grep -q 'direnv allow' "$tmp/calls"; then fail=$((fail+1)); echo "FAIL: direnv allow ran with a devenv.local.nix"; else pass=$((pass+1)); fi
mkdir -p "$tmp/ownrc"; echo 'use devenv' >"$tmp/ownrc/.envrc"; echo '{ }' >"$tmp/ownrc/devenv.local.nix"
repo_dir="$tmp/ownrc" shell_init
check "own .envrc: devenv.local.nix approved with it" 'not approved: \.envrc devenv\.local\.nix;'
# claudeCode.enable.
on='^    claudeCode\.enable = true; +# the CLI for tmux/ajmux sessions; the VS Code extension brings its own$'
off='^    # claudeCode\.enable = true; +# claude, tmux and jq in this shell'
# No claude on the host PATH (acme/plain above): on, allow_unfree with it,
# and the report says so, the dry run included.
has   "no host claude: claudeCode.enable on"   "$tmp/code/acme/plain/devenv.nix" "$on"
has   "no host claude: allow_unfree"           "$tmp/code/acme/plain/devenv.yaml" '^allow_unfree: true +# for ai-jail\.claudeCode\.enable in devenv\.nix: claude-code is unfree$'
check "no host claude: reported"               'claude +none on the host PATH: claudeCode\.enable = true in devenv\.nix, allow_unfree: true in devenv\.yaml'
init --dry-run acme/demo
check "no host claude: reported in the dry run" 'claude +none on the host PATH: claudeCode\.enable = true'
# A claude on the host PATH (a native install, a profile, the home module):
# both stay commented out.
mkdir -p "$tmp/hostbin"; printf '#!/bin/sh\n' >"$tmp/hostbin/claude"; chmod +x "$tmp/hostbin/claude"
HOST_PATH="$tmp/hostbin" init --no-shell acme/hosted
has   "host claude: claudeCode.enable commented" "$tmp/code/acme/hosted/devenv.nix" "$off"
lacks "host claude: claudeCode.enable not set"   "$tmp/code/acme/hosted/devenv.nix" '^ *claudeCode\.enable'
has   "host claude: allow_unfree commented"      "$tmp/code/acme/hosted/devenv.yaml" '^# allow_unfree: true +# for ai-jail\.claudeCode\.enable'
lacks "host claude: allow_unfree not set"        "$tmp/code/acme/hosted/devenv.yaml" '^allow_unfree'
check "host claude: reported"                    "claude +$tmp/hostbin/claude on the host PATH: claudeCode\\.enable left commented out in devenv\\.nix"
# A claude only in a store directory (init run from a repo shell that has
# one) or under ~/.vscode-server (the extension's copy) is not the host's.
mkdir -p "$tmp/store/abc-claude-code/bin" "$tmp/home/.vscode-server/bin/x/bin"
cp "$tmp/hostbin/claude" "$tmp/store/abc-claude-code/bin/claude"; cp "$tmp/hostbin/claude" "$tmp/home/.vscode-server/bin/x/bin/claude"
STORE="$tmp/store" HOST_PATH="$tmp/store/abc-claude-code/bin:$tmp/home/.vscode-server/bin/x/bin" init --no-shell acme/shelled
has   "shell's claude only: claudeCode.enable on" "$tmp/code/acme/shelled/devenv.nix" "$on"
has   "shell's claude only: allow_unfree"         "$tmp/code/acme/shelled/devenv.yaml" '^allow_unfree: true'
check "shell's claude only: reported as none"     'claude +none on the host PATH'
# ... and one after them on PATH still is.
STORE="$tmp/store" HOST_PATH="$tmp/store/abc-claude-code/bin:$tmp/hostbin" init --dry-run acme/demo
check "host claude after a shell's: found"       "claude +$tmp/hostbin/claude on the host PATH"

echo "aj-init-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
