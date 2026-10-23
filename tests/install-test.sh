#!/usr/bin/env bash
#   install-test.sh <scripts/install.sh>
#
# scripts/install.sh with every host command stubbed (curl, the installer it
# fetches, sudo, rpm, systemctl, nix) and a fake os-release: the
# nix-installer route (fetched only when nix is absent; --yes or a terminal
# for its confirmation), the Fedora route (dnf, the socket, no installer),
# what reaches bootstrap (the ref: this checkout, HARNESS_REF, or the
# published repo when piped; the root steps; flakes on), the init of the
# checkout, the NixOS route (no installer, the nix.settings block printed),
# and the flags that stop it. Assumes no nix on the test's own PATH and no
# controlling terminal, which the Nix build sandbox guarantees.
set -uo pipefail
script="${1:?usage: install-test.sh <scripts/install.sh>}"
pass=0; fail=0
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
log="$tmp/calls"

# A checkout: the script under scripts/, flake.nix and .envrc beside it.
mkdir -p "$tmp/checkout/scripts" "$tmp/bin" "$tmp/nixbin" "$tmp/home"
cp "$script" "$tmp/checkout/scripts/install.sh"
touch "$tmp/checkout/flake.nix" "$tmp/checkout/.envrc"

stub() { # stub <dir> <name> <body>: logs its argv to $CALLS, then runs <body>
  printf '#!/bin/sh\necho "%s $*" >>"$CALLS"\n%s\n' "$2" "$3" >"$1/$2"; chmod +x "$1/$2"
}
# What curl "downloads": an installer that logs and does nothing else.
printf '#!/bin/sh\necho "installer $*" >>"$CALLS"\n' >"$tmp/installer"
stub "$tmp/bin" curl 'o=""; while [ $# -gt 0 ]; do [ "$1" = -o ] && o="$2"; shift; done; [ -z "$o" ] || cp "$INSTALLER" "$o"'
stub "$tmp/bin" sudo 'exit 0'
stub "$tmp/bin" rpm 'exit 1'
stub "$tmp/bin" systemctl 'exit 1'
# nix: logs what bootstrap and init would see.
stub "$tmp/nixbin" nix 'echo "env HARNESS_REF=$HARNESS_REF HARNESS_ROOT_PACKAGES=[$HARNESS_ROOT_PACKAGES] HARNESS_ROOT_STEPS=[$HARNESS_ROOT_STEPS] NIX_CONFIG=[$NIX_CONFIG]" >>"$CALLS"
case "$*" in *" bootstrap"*|*" bootstrap "*) exit "${BOOTSTRAP_RC:-0}" ;; esac'
# What the installer route sources afterwards: puts nix on PATH.
printf 'PATH=%s:$PATH\n' "$tmp/nixbin" >"$tmp/nix-daemon.sh"

# run <os-id> <version> <cwd> [args...]: the script with nix absent, unless
# WITH_NIX=1; stdin closed (no terminal). Sets out and rc, empties the log.
run() {
  local id="$1" ver="$2" cwd="$3" path="$tmp/bin:$PATH"; shift 3
  [ "${WITH_NIX:-0}" = 1 ] && path="$tmp/nixbin:$path"
  printf 'ID=%s\nVERSION_ID="%s"\nPRETTY_NAME="%s %s"\n' "$id" "$ver" "$id" "$ver" >"$tmp/os-release"
  : >"$log"
  out=$(cd "$cwd" && env -i HOME="$tmp/home" PATH="$path" TMPDIR="$tmp" CALLS="$log" INSTALLER="$tmp/installer" \
    HARNESS_OS_RELEASE="$tmp/os-release" HARNESS_NIX_PROFILE_SH="$tmp/nix-daemon.sh" ${HARNESS_REF:+HARNESS_REF="$HARNESS_REF"} \
    HARNESS_NIXOS_MARKER=/var/empty/none HARNESS_NIX_CONF="$tmp/nix.conf" ${BOOTSTRAP_RC:+BOOTSTRAP_RC="$BOOTSTRAP_RC"} \
    bash "$tmp/checkout/scripts/install.sh" "$@" 2>&1 </dev/null); rc=$?
}
called()   { if grep -q -E -e "$2" "$log"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (/$2/ not in the calls)"; sed 's/^/  /' "$log"; fi; }
uncalled() { if grep -q -E -e "$2" "$log"; then fail=$((fail+1)); echo "FAIL: $1 (/$2/ in the calls)"; sed 's/^/  /' "$log"; else pass=$((pass+1)); fi; }
says()     { if [[ "$out" =~ $2 ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (/$2/)"; printf '%s\n' "$out" | sed 's/^/  /'; fi; }
exits()    { if [ "$rc" = "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (want exit $2, got $rc)"; printf '%s\n' "$out" | sed 's/^/  /'; fi; }

# Ubuntu, no nix, --yes: the installer, then bootstrap and init with the
# checkout as the ref, the installer step recorded, flakes on, no sudo here
# (the installer asks itself).
run ubuntu 24.04 "$tmp/checkout" --yes
exits "fresh host" 0
called "installer fetched"         '^curl .*artifacts\.nixos\.org/nix-installer'
called "installer run, no-confirm" '^installer install --no-confirm$'
called "bootstrap from the checkout" "^nix run path:$tmp/checkout#harness -- bootstrap --yes$"
called "installer step recorded"   'HARNESS_ROOT_STEPS=\[nix-installer\]'
called "no packages recorded"      'HARNESS_ROOT_PACKAGES=\[\]'
called "flakes on for nix"         'NIX_CONFIG=\[extra-experimental-features = nix-command flakes\]'
called "init of the checkout"      "^nix run path:$tmp/checkout#harness -- init $tmp/checkout --yes$"
uncalled "no dnf off fedora"       'dnf'
uncalled "no sudo of our own"      '^sudo'

# Bootstrap's report has a MISSING line (exit 1): init still runs on the
# checkout and the exit code comes through (Ubuntu, 2026-10-21: tmux and
# claude come from the shell init builds).
BOOTSTRAP_RC=1 WITH_NIX=1 run ubuntu 24.04 "$tmp/checkout" --yes
exits "bootstrap missing: exit kept" 1
called "bootstrap missing: init still runs" "-- init $tmp/checkout --yes$"
says "bootstrap missing: says so"   'init runs anyway'

# nix present: no installer, nothing recorded.
WITH_NIX=1 run ubuntu 24.04 "$tmp/checkout" --yes
exits "re-run" 0
uncalled "no second installer"     '^curl|^installer'
called "nothing recorded"          'HARNESS_ROOT_STEPS=\[\]'
called "bootstrap again"           '-- bootstrap --yes$'

# No terminal and no --yes: refused before the installer runs.
run ubuntu 24.04 "$tmp/checkout"
exits "no terminal" 1
says "asks for --yes"              'run with --yes'
uncalled "installer not run"       '^installer'
uncalled "no bootstrap"            '^nix run'

# From another directory: still this checkout.
WITH_NIX=1 run ubuntu 24.04 "$tmp" --yes
called "ref is the checkout"       "^nix run path:$tmp/checkout#harness -- bootstrap"
called "init of the checkout"      "-- init $tmp/checkout"

# Piped into bash, no checkout: the published ref, no init.
: >"$log"
out=$(cd "$tmp" && env -i HOME="$tmp/home" PATH="$tmp/nixbin:$tmp/bin:$PATH" TMPDIR="$tmp" CALLS="$log" INSTALLER="$tmp/installer" \
  HARNESS_OS_RELEASE="$tmp/os-release" HARNESS_NIX_PROFILE_SH="$tmp/nix-daemon.sh" \
  bash -s -- --yes <"$tmp/checkout/scripts/install.sh" 2>&1); rc=$?
exits "piped" 0
called "published ref"             '^nix run github:bilibo/claude-nix-harness#harness -- bootstrap --yes$'
uncalled "no init without a checkout" ' init '

# HARNESS_REF wins over the checkout; init still runs on the checkout.
HARNESS_REF=github:bilibo/claude-nix-harness WITH_NIX=1 run ubuntu 24.04 "$tmp/checkout" --yes
called "HARNESS_REF wins"          '^nix run github:bilibo/claude-nix-harness#harness -- bootstrap'
called "init on the checkout"      "github:bilibo/claude-nix-harness#harness -- init $tmp/checkout"

# --no-init, and which flags reach bootstrap and init.
WITH_NIX=1 run ubuntu 24.04 "$tmp/checkout" --yes --no-init
uncalled "--no-init"               ' init '
called "--no-init not passed on"   '-- bootstrap --yes$'
WITH_NIX=1 run ubuntu 24.04 "$tmp/checkout" --verbose --no-account-sync --yes
called "bootstrap flags"           '-- bootstrap --verbose --no-account-sync --yes$'
called "init flags"                "-- init $tmp/checkout --verbose --yes$"

# --check: nothing runs. --dry-run without nix: the installer is reported,
# nothing runs; with nix: bootstrap --dry-run, then init --dry-run.
run ubuntu 24.04 "$tmp/checkout" --check
exits "--check" 0
says "check reports"               'install.sh --check: nothing changed'
uncalled "check runs nothing"      '^curl|^installer|^nix|^sudo'
run ubuntu 24.04 "$tmp/checkout" --dry-run
exits "--dry-run" 0
says "dry run names the installer" 'would run: curl'
uncalled "dry run runs nothing"    '^curl|^installer|^nix'
WITH_NIX=1 run ubuntu 24.04 "$tmp/checkout" --dry-run
called "bootstrap --dry-run"       '-- bootstrap --dry-run$'
called "init --dry-run"            '-- init .* --dry-run$'

# Fedora 44: dnf, the socket, no installer; the packages reach bootstrap.
WITH_NIX=1 run fedora 44 "$tmp/checkout" --yes
exits "fedora" 0
called "dnf"                       '^sudo dnf install -y nix nix-daemon bubblewrap socat tmux jq git-core policycoreutils-python-utils$'
called "socket"                    '^sudo systemctl enable --now nix-daemon.socket$'
uncalled "no installer on fedora"  '^curl|^installer'
called "packages recorded"         'HARNESS_ROOT_PACKAGES=\[nix nix-daemon bubblewrap socat tmux jq git-core policycoreutils-python-utils\]'
called "socket recorded"           'HARNESS_ROOT_STEPS=\[nix-daemon.socket\]'
# Fedora 43 has no nix package: the installer route.
WITH_NIX=1 run fedora 43 "$tmp/checkout" --yes
uncalled "fedora 43 is the installer route" 'dnf'

# NixOS: no installer, no dnf, no sudo; nix.conf is the system's, so the
# nix.settings block is printed while it lacks the lines, then bootstrap.
: >"$tmp/nix.conf"
WITH_NIX=1 run nixos 26.11 "$tmp/checkout" --yes
exits "nixos" 0
uncalled "no installer on nixos"   '^curl|^installer'
uncalled "no dnf on nixos"         'dnf'
uncalled "no sudo on nixos"        '^sudo'
says "nixos named"                 'NixOS: nix from the system configuration, no installer'
says "nix.settings printed"        'nix\.settings = \{.*experimental-features = \[ "nix-command" "flakes" \];.*substituters = \[ "https://devenv\.cachix\.org" \];'
called "bootstrap on nixos"        "^nix run path:$tmp/checkout#harness -- bootstrap --yes$"
called "nothing recorded on nixos" 'HARNESS_ROOT_STEPS=\[\]'
printf 'experimental-features = nix-command flakes\nextra-substituters = https://devenv.cachix.org\n' >"$tmp/nix.conf"
WITH_NIX=1 run nixos 26.11 "$tmp/checkout" --yes
says "nixos again"                 'NixOS: nix from the system configuration'
if [[ "$out" =~ nix\.settings ]]; then fail=$((fail+1)); echo "FAIL: nix.settings printed although nix.conf has the lines"; else pass=$((pass+1)); fi
# Without nix there is nothing to run: refused, nothing downloaded.
run nixos 26.11 "$tmp/checkout" --yes
exits "nixos without nix" 1
says "says why"                    'NixOS without nix on PATH'
uncalled "still no installer"      '^curl|^installer'

echo "install-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
