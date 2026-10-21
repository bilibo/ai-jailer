#!/usr/bin/env bash
#   harness-doctor-test.sh <path-to-harness> <project-settings.json>
#
# `harness doctor` on a host that has nothing: an empty HOME, a PATH with no
# nix, claude, code, direnv or tmux (the Nix build sandbox is such a host).
# It must report MISSING lines, run to its summary and exit 1, never stop
# early. Then the repo part, in three fake repos: the settings file as a
# store symlink (its hooks must run), as a dangling symlink, as a plain file.
set -uo pipefail
harness="${1:?usage: harness-doctor-test.sh <harness> <project-settings.json>}"
settings="${2:?usage: harness-doctor-test.sh <harness> <project-settings.json>}"
pass=0; fail=0
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home"

# doctor <dir> [<path>]: harness doctor in <dir> with nothing (or only <path>)
# on PATH; sets out and rc.
doctor() {
  out=$(cd "$1" && env -i HOME="$tmp/home" PATH="${2:-/var/empty}" TMPDIR="$tmp" "$harness" doctor 2>&1); rc=$?
}
check() { # check <description> <want-regex>
  if [[ "$out" =~ $2 ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (/$2/)"; printf '%s\n' "$out" | sed 's/^/  /'; fi
}
refute() { # refute <description> <forbidden-regex>
  if [[ "$out" =~ $2 ]]; then fail=$((fail+1)); echo "FAIL: $1 (/$2/ matched)"; printf '%s\n' "$out" | sed 's/^/  /'; else pass=$((pass+1)); fi
}
exits() { # exits <description> <want>
  if [ "$rc" = "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (want exit $2, got $rc)"; fi
}

mkdir -p "$tmp/empty"
doctor "$tmp/empty"
exits "doctor exits 1 when something is missing" 1
check "nix reported missing"    'MISSING nix'
check "claude reported missing" 'MISSING claude'
check "direnv reported missing" 'MISSING direnv'
check "ran to the summary"      'harness doctor: [0-9]+ missing, [0-9]+ warnings'
refute "no shell error"         'unbound variable|syntax error|line [0-9]+:|command not found'
refute "no repo part outside a repo" 'repo: '

mkdir -p "$tmp/repo/.claude"; touch "$tmp/repo/.envrc"
ln -s "$settings" "$tmp/repo/.claude/settings.json"
doctor "$tmp/repo"
exits "doctor in a repo, nothing on PATH" 1
check "repo part runs"          'repo: '
check "store symlink accepted"  'ok    \.claude/settings\.json -> /nix/store/'
check "hooks run"               'ok    [1-9][0-9]* hooks in \.claude/settings\.json runnable'
check "direnv missing in repo"  'MISSING direnv not on PATH'
refute "no unrunnable hook"     'hook not runnable'

rm "$tmp/repo/.claude/settings.json"; ln -s /nix/store/does-not-exist "$tmp/repo/.claude/settings.json"
doctor "$tmp/repo"
check "dangling symlink"        'MISSING \.claude/settings\.json is a dangling symlink'

rm "$tmp/repo/.claude/settings.json"; echo '{}' >"$tmp/repo/.claude/settings.json"
doctor "$tmp/repo"
check "plain file"              'MISSING \.claude/settings\.json is a plain file'
check "plain file without hooks" 'MISSING no runnable hook'

# Inside a session the sandbox masks the file as a character device: say so,
# never report the repo as broken. (-c follows the symlink.)
rm "$tmp/repo/.claude/settings.json"; ln -s /dev/null "$tmp/repo/.claude/settings.json"
doctor "$tmp/repo"
check "sandbox mask reported"   'warn  \.claude/settings\.json is masked by the sandbox'
refute "mask is no repo verdict" 'no runnable hook|plain file|dangling symlink|points outside'

# A `code` that answers nothing (the same sandbox): no extension verdict.
mkdir -p "$tmp/bin"; printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/code"; chmod +x "$tmp/bin/code"
doctor "$tmp/empty" "$tmp/bin"
check "silent code reported"    'warn  code is on PATH but answers nothing'
refute "no extension verdict"   'VS Code extension'

out=$("$harness" --version 2>&1); rc=$?
exits "--version" 0; check "--version prints the revision" '^harness .+'
out=$("$harness" --help 2>&1); rc=$?
exits "--help" 0; check "--help lists the commands" 'bootstrap.*upgrade.*doctor.*init.*check.*reset'
out=$("$harness" doctor --help 2>&1); rc=$?
exits "doctor --help" 0; check "doctor --help is the bootstrap header" 'harness reset'
out=$("$harness" frobnicate 2>&1); rc=$?
exits "unknown command" 64

echo "harness-doctor-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
