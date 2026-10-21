#!/usr/bin/env bash
#   mod-validate-test.sh <marketplace dir> [claude]
#
# `claude plugin validate --strict` over the built marketplace and each mod
# in it (docs/sessions.md section 6: the validate output is the contract),
# then `claude plugin test` for every mod that ships tests. Needs a claude
# binary: the host's, or the one given. claude-code is unfree in nixpkgs, so
# `nix flake check` carries this only when the evaluator allows unfree
# packages; otherwise run it by hand against `nix build .#managed-mods`:
#   bash tests/mod-validate-test.sh result/plugins
set -euo pipefail
dir="${1:?usage: mod-validate-test.sh <marketplace dir> [claude]}"
claude="${2:-claude}"
export HOME="${HOME:-${TMPDIR:-/tmp}}"
export DISABLE_TELEMETRY=1 DISABLE_AUTOUPDATER=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

echo "== marketplace: $dir"
"$claude" plugin validate --strict "$dir"
for mod in $(jq -r '.plugins[].source' "$dir/.claude-plugin/marketplace.json"); do
  echo "== mod: $mod"
  "$claude" plugin validate --strict "$dir/$mod"
  if ls "$dir/$mod"/tests/*.test.ts >/dev/null 2>&1; then
    "$claude" plugin test "$dir/$mod"
  fi
done
echo "mod-validate-test: ok"
