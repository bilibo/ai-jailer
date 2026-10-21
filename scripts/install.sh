#!/usr/bin/env bash
#   curl -fsSL https://raw.githubusercontent.com/bilibo/claude-nix-harness/main/scripts/install.sh | bash -s -- [flags]
#   scripts/install.sh [--check] [harness bootstrap flags]
#
# The steps of `harness bootstrap` that have to run before `nix run` works,
# on Fedora 44 or newer (the first release that packages nix and nix-daemon):
# `dnf install` of nix, nix-daemon and what the sandbox and the harness call;
# the SELinux label systemd needs to create the daemon socket in /nix; the
# socket itself, which the nix-daemon package leaves disabled and without
# which a non-root `nix run` has no store. Then
#   exec nix run "${HARNESS_REF:-github:bilibo/claude-nix-harness}#harness" -- bootstrap "$@"
# which writes nix.conf and the rest, finds these steps done, and records
# everything in its receipt; what was done here reaches it through
# HARNESS_ROOT_PACKAGES and HARNESS_ROOT_STEPS. --check reports the steps
# and changes nothing; --dry-run does the same, then hands over to
# bootstrap's --dry-run when Nix can already run.
# From a checkout: HARNESS_REF=path:$PWD scripts/install.sh.
# shellcheck disable=SC1091  # /etc/os-release is not an input
set -euo pipefail

# One function, called on the last line: piped into bash, nothing runs before
# the whole script has arrived.
main() {
  local CHECK=0 DRY=0 a p f need=() done_steps=() pending=0 ref="${HARNESS_REF:-github:bilibo/claude-nix-harness}"
  for a in "$@"; do
    case "$a" in --check) CHECK=1 ;; --dry-run) DRY=1 ;; esac
  done
  die() { echo "install.sh: $*" >&2; exit 1; }
  # root <command...>: through sudo; under --check and --dry-run only printed.
  root() {
    if [ "$CHECK" = 1 ] || [ "$DRY" = 1 ]; then echo "    would run: sudo $*"; pending=1
    else sudo "$@"; fi
  }

  [ -r /etc/os-release ] && . /etc/os-release
  [ "${ID:-}" = fedora ] && [ "${VERSION_ID:-0}" -ge 44 ] 2>/dev/null \
    || die "Fedora 44 or newer only (found ${PRETTY_NAME:-no /etc/os-release}): the first release that packages nix and nix-daemon. Elsewhere install Nix, then: nix run $ref#harness -- doctor"
  [ "$(id -u)" != 0 ] || die "run as your own user; sudo is used where root is needed"

  for p in nix nix-daemon bubblewrap socat tmux jq git-core policycoreutils-python-utils; do
    rpm -q "$p" >/dev/null 2>&1 || need+=("$p")
  done
  if [ ${#need[@]} -gt 0 ]; then
    printf '\n==> dnf install %s\n' "${need[*]}"
    root dnf install -y "${need[@]}"
  fi

  # SELinux: /nix is default_t without a policy, and systemd may not create
  # a socket there (bootstrap.sh has the detail); label the socket directory
  # var_run_t, the type /run has.
  if [ "$(getenforce 2>/dev/null)" != Disabled ] && ! matchpathcon -n /nix/var/nix/daemon-socket/socket 2>/dev/null | grep -q var_run_t; then
    printf '\n==> SELinux: label /nix/var/nix/daemon-socket as var_run_t so systemd can create the daemon socket\n'
    root semanage fcontext -a -t var_run_t '/nix/var/nix/daemon-socket(/.*)?'
    root restorecon -RF /nix/var/nix/daemon-socket
    done_steps+=(selinux)
  fi
  if ! systemctl is-enabled -q nix-daemon.socket 2>/dev/null || ! systemctl is-active -q nix-daemon.socket 2>/dev/null; then
    printf '\n==> enable the nix-daemon socket\n'
    root systemctl enable --now nix-daemon.socket
    done_steps+=(nix-daemon.socket)
  fi
  if [ "$CHECK" = 1 ]; then echo; echo "install.sh --check: nothing changed; next would be: nix run $ref#harness -- bootstrap"; exit 0; fi

  # Fedora's profile.d/nix-daemon.sh only knows the legacy CA bundle paths.
  for f in /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt; do
    [ -n "${NIX_SSL_CERT_FILE:-}" ] || [ ! -r "$f" ] || export NIX_SSL_CERT_FILE="$f"
  done
  if ! command -v nix >/dev/null || [ "$pending" = 1 ]; then
    [ "$DRY" = 1 ] || die "nix not on PATH after the dnf step"
    echo; echo "install.sh --dry-run: next would be: nix run $ref#harness -- bootstrap $*"; exit 0
  fi
  # Only in a real run: under --dry-run with nothing pending, the lists are empty.
  [ "$DRY" = 1 ] && done_steps=()
  export HARNESS_REF="$ref" HARNESS_ROOT_PACKAGES="${need[*]}" HARNESS_ROOT_STEPS="${done_steps[*]}"
  printf '\n==> nix run %s#harness -- bootstrap %s\n' "$ref" "$*"
  exec nix run "$ref#harness" -- bootstrap "$@"
}

main "$@"
