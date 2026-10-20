#!/usr/bin/env bash
#   curl -fsSL https://raw.githubusercontent.com/bilibo/claude-nix-harness/main/scripts/install.sh | bash -s -- [flags]
#   scripts/install.sh [--check] [--dry-run] [--trusted-user] [harness bootstrap flags]
#
# The part of `harness bootstrap` that has to run before Nix exists, on Fedora
# 44 or newer (the first release that packages nix and nix-daemon), then
#   exec nix run "${HARNESS_REF:-github:bilibo/claude-nix-harness}#harness" -- bootstrap --no-root "$@"
# The root steps, each checked before it runs, through sudo: dnf install of
# nix, nix-daemon and what the sandbox and the harness call; the harness block
# in /etc/nix/nix.conf (the devenv cache, trusted-users only with
# --trusted-user); the SELinux label for the daemon socket; nix-daemon.socket.
# What they did reaches the bootstrap's receipt through HARNESS_ROOT_PACKAGES
# and HARNESS_ROOT_STEPS. --check reports the steps and changes nothing;
# --dry-run does the same and passes on to `harness bootstrap --dry-run`.
# From a checkout: HARNESS_REF=path:$PWD scripts/install.sh.
# shellcheck disable=SC1091  # /etc/os-release is not an input
set -euo pipefail

# One function, called on the last line: piped into bash, nothing runs before
# the whole script has arrived.
main() {
  local MARK_BEGIN="# --- claude-nix-harness (scripts/bootstrap-fedora.sh) ---"   # bootstrap.sh's, byte for byte
  local MARK_END="# --- end claude-nix-harness ---"
  local DEVENV_CACHE="https://devenv.cachix.org"
  local DEVENV_KEY="devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
  local CHECK=0 DRY=0 TRUSTED=0 a p f conf=/etc/nix/nix.conf want tmp need=() done_steps=()
  for a in "$@"; do
    case "$a" in --check) CHECK=1 ;; --dry-run) DRY=1 ;; --trusted-user) TRUSTED=1 ;; esac
  done
  die() { echo "install.sh: $*" >&2; exit 1; }
  step() { printf '\n==> %s\n' "$*"; }
  # root <command...>: through sudo; under --check and --dry-run only printed.
  root() { if [ "$CHECK" = 1 ] || [ "$DRY" = 1 ]; then echo "    would run: sudo $*"; else sudo "$@"; fi; }

  [ -r /etc/os-release ] && . /etc/os-release
  [ "${ID:-}" = fedora ] && [ "${VERSION_ID:-0}" -ge 44 ] 2>/dev/null \
    || die "Fedora 44 or newer only (found ${PRETTY_NAME:-no /etc/os-release}): the first release that packages nix and nix-daemon. Elsewhere install Nix, then: nix run ${HARNESS_REF:-github:bilibo/claude-nix-harness}#harness -- doctor"
  [ "$(id -u)" != 0 ] || die "run as your own user; sudo is used where root is needed"

  for p in nix nix-daemon bubblewrap socat tmux jq git-core policycoreutils-python-utils; do
    rpm -q "$p" >/dev/null 2>&1 || need+=("$p")
  done
  if [ ${#need[@]} -gt 0 ]; then step "dnf install ${need[*]}"; root dnf install -y "${need[@]}"; fi

  # Fedora's nix.conf already enables nix-command and flakes; everything but a
  # previous harness block, then the block.
  want=$(awk -v b="$MARK_BEGIN" -v e="$MARK_END" '$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$conf" 2>/dev/null || true)
  want="${want:+$want
}$MARK_BEGIN
extra-substituters = $DEVENV_CACHE
extra-trusted-public-keys = $DEVENV_KEY"
  [ "$TRUSTED" = 1 ] && want="$want
trusted-users = root $USER"
  want="$want
$MARK_END"
  if [ "$(cat "$conf" 2>/dev/null)" != "$want" ]; then
    step "write $conf (harness block: devenv cache$([ "$TRUSTED" = 1 ] && echo ", trusted-users"))"
    if [ "$CHECK" = 1 ] || [ "$DRY" = 1 ]; then echo "    would write it"
    else tmp=$(mktemp); printf '%s\n' "$want" >"$tmp"; sudo install -m 0644 -o root -g root "$tmp" "$conf"; rm -f "$tmp"; fi
    systemctl is-active -q nix-daemon.service && root systemctl restart nix-daemon.service
  fi
  done_steps+=(nix.conf)

  # SELinux: systemd may not create the daemon socket in a default_t /nix
  # (bootstrap.sh has the detail); label the directory var_run_t, like /run.
  if [ "$(getenforce 2>/dev/null)" != Disabled ] && ! matchpathcon -n /nix/var/nix/daemon-socket/socket 2>/dev/null | grep -q var_run_t; then
    step "SELinux: label /nix/var/nix/daemon-socket as var_run_t so systemd can create the daemon socket"
    root semanage fcontext -a -t var_run_t '/nix/var/nix/daemon-socket(/.*)?'
    root restorecon -RF /nix/var/nix/daemon-socket
    done_steps+=(selinux)
  fi

  if ! systemctl is-enabled -q nix-daemon.socket 2>/dev/null || ! systemctl is-active -q nix-daemon.socket 2>/dev/null; then
    step "enable the nix-daemon socket"; root systemctl enable --now nix-daemon.socket; done_steps+=(nix-daemon.socket)
  fi

  if [ "$CHECK" = 1 ]; then echo; echo "install.sh --check: nothing changed; next would be: nix run ${HARNESS_REF:-github:bilibo/claude-nix-harness}#harness -- bootstrap --no-root"; exit 0; fi
  # Fedora's profile.d/nix-daemon.sh only knows the legacy CA bundle paths.
  for f in /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt; do
    [ -n "${NIX_SSL_CERT_FILE:-}" ] || [ ! -r "$f" ] || export NIX_SSL_CERT_FILE="$f"
  done
  if ! command -v nix >/dev/null; then
    [ "$DRY" = 1 ] || die "nix not on PATH after the dnf step"
    echo; echo "install.sh --dry-run: next would be: nix run ${HARNESS_REF:-github:bilibo/claude-nix-harness}#harness -- bootstrap --no-root $*"; exit 0
  fi
  export HARNESS_REF="${HARNESS_REF:-github:bilibo/claude-nix-harness}" HARNESS_ROOT_PACKAGES="${need[*]}" HARNESS_ROOT_STEPS="${done_steps[*]}"
  step "nix run $HARNESS_REF#harness -- bootstrap --no-root $*"
  exec nix run "${HARNESS_REF:-github:bilibo/claude-nix-harness}#harness" -- bootstrap --no-root "$@"
}

main "$@"
