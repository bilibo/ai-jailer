#!/usr/bin/env bash
# Tests for the ccode wrapper's project resolution. Uses `ccode -n` (dry run), which
# prints what it would do instead of touching tmux.
#
#   ccode-test.sh <path-to-ccode>
#
# Builds a fake code root under a temp dir: <root>/acme/infra with a worktree
# and a subdirectory, plus a directory outside the root.
set -uo pipefail
ccode="${1:?usage: ccode-test.sh <ccode>}"
pass=0; fail=0
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
root="$tmp/code/git"
mkdir -p "$root/acme/infra/modules/net" "$root/acme/infra/.claude/worktrees/wt1" "$root/acme/app" "$tmp/elsewhere"
export HARNESS_CODE_ROOT="$root"
unset HARNESS_PROJECT

# check <want-exit> <want-output-regex> <cwd> <args...>
check() {
  local want="$1" re="$2" dir="$3"; shift 3
  local out got
  out=$(cd "$dir" && "$ccode" -n "$@" 2>&1); got=$?
  if [ "$got" = "$want" ] && [[ "$out" =~ $re ]]; then pass=$((pass+1)); else
    fail=$((fail+1)); echo "FAIL (want $want /$re/, got $got): cd $dir && ccode -n $*"; echo "  $out"; fi
}
ok() { check 0 "$@"; }

# Explicit <customer>/<repo>, from anywhere.
ok "session=acme-infra repo=$root/acme/infra" "$tmp/elsewhere" acme/infra
ok "session=acme-infra repo=$root/acme/infra args=--worktree" "$tmp/elsewhere" acme/infra --worktree
ok "session=acme-app repo=$root/acme/app" "$root/acme/infra" acme/app
# No argument: the repo containing the current directory.
ok "session=acme-infra repo=$root/acme/infra" "$root/acme/infra"
ok "session=acme-infra repo=$root/acme/infra" "$root/acme/infra/modules/net"
ok "session=acme-infra repo=$root/acme/infra" "$root/acme/infra/.claude/worktrees/wt1"
# Only claude args: project from the current directory.
ok "session=acme-infra repo=$root/acme/infra args=-p hi" "$root/acme/infra" -p hi
ok "session=acme-infra repo=$root/acme/infra args=--worktree" "$root/acme/infra/modules" --worktree
# A path instead of a name.
ok "session=acme-infra repo=$root/acme/infra" "$tmp/elsewhere" "$root/acme/infra"
ok "session=acme-infra repo=$root/acme/infra" "$root/acme" infra
ok "session=acme-infra repo=$root/acme/infra" "$root/acme/infra" .
ok "session=acme-app repo=$root/acme/app" "$root/acme/infra" ../app
# HARNESS_PROJECT (exported by the devenv shell) wins over cwd.
HARNESS_PROJECT=acme/app ok "session=acme-app repo=$root/acme/app" "$root/acme/infra"
# Failures: outside the root, missing repo, customer only.
check 64 "usage" "$tmp/elsewhere"
check 66 "no such repo" "$tmp/elsewhere" acme/missing
check 66 "no such repo" "$tmp/elsewhere" infra
check 66 "not under" "$tmp" elsewhere
check 66 "not under" "$root" acme

echo "ccode-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
