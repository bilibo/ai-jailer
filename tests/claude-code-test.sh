#!/usr/bin/env bash
#   claude-code-test.sh <path-to-claude-code>
#
# pkgs/claude-code.nix: the wrapper no longer sets LD_LIBRARY_PATH (the
# binary wrapper embeds its own invocation text, so the name must be absent
# from it), the binary itself is untouched (no RUNPATH: the patch broke
# 2.1.303, changelog 2026-10-27), and it still starts: `claude --version`
# names the package version. Needs patchelf and binutils on PATH.
set -uo pipefail
pkg="${1:?usage: claude-code-test.sh <claude-code>}"
pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $*"; }

wrapper="$pkg/bin/claude"; binary="$pkg/bin/.claude-wrapped"
[ -x "$wrapper" ] && ok || bad "$wrapper is not executable"
[ -x "$binary" ] && ok || bad "$binary is not executable (the wrapper layout changed)"

if strings "$wrapper" | grep -q LD_LIBRARY_PATH; then bad "the wrapper still names LD_LIBRARY_PATH"; else ok; fi
# makeBinaryWrapper embeds its arguments quoted: --prefix 'PATH' ':' '...'.
if strings "$wrapper" | grep -q -- "--prefix 'PATH' ':'"; then ok; else bad "the wrapper lost its PATH prefix (the whole line was dropped, not one argument)"; fi

rpath=$(patchelf --print-rpath "$binary" 2>&1)
case "$rpath" in *alsa-lib*) bad "alsa-lib is back on the binary's RUNPATH: '$rpath' (the patch segfaults 2.1.303)" ;; *) ok ;; esac

export HOME="${TMPDIR:-/tmp}/claude-code-test-home"; mkdir -p "$HOME"
v=$("$wrapper" --version 2>&1); rc=$?
want=$(basename "$pkg" | sed 's/^[^-]*-claude-code-//')
if [ "$rc" = 0 ] && [[ "$v" == "$want"* ]]; then ok; else bad "claude --version: exit $rc, '$v' (want $want)"; fi
# Inside the wrapper's process the variable is still absent: the binary
# prints its environment through no flag, so the wrapper's embedded text
# above is the check; this one guards the test's own premise.
if [ -z "${LD_LIBRARY_PATH:-}" ]; then ok; else bad "LD_LIBRARY_PATH set in the test environment: ${LD_LIBRARY_PATH}"; fi

echo "claude-code-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
