#!/usr/bin/env bash
#   curl -fsSL https://raw.githubusercontent.com/bilibo/claude-nix-harness/main/scripts/install.sh | bash -s -- [flags]
#   scripts/install.sh [--check] [harness bootstrap flags]
#
# The one step of `harness bootstrap` that has to run before Nix exists, on
# Fedora 44 or newer (the first release that packages nix and nix-daemon):
# `dnf install` of nix, nix-daemon and what the sandbox and the harness call.
# Then
#   exec nix run "${HARNESS_REF:-github:bilibo/claude-nix-harness}#harness" -- bootstrap "$@"
# which does the other root steps itself (nix.conf, the SELinux label, the
# daemon socket) and records everything in its receipt; the packages
# installed here reach it through HARNESS_ROOT_PACKAGES. --check reports the
# dnf step and changes nothing; --dry-run is bootstrap's and never sudo.
# From a checkout: HARNESS_REF=path:$PWD scripts/install.sh.
# shellcheck disable=SC1091  # /etc/os-release is not an input
set -euo pipefail

# One function, called on the last line: piped into bash, nothing runs before
# the whole script has arrived.
main() {
  local CHECK=0 DRY=0 a p f need=() ref="${HARNESS_REF:-github:bilibo/claude-nix-harness}"
  for a in "$@"; do
    case "$a" in --check) CHECK=1 ;; --dry-run) DRY=1 ;; esac
  done
  die() { echo "install.sh: $*" >&2; exit 1; }

  [ -r /etc/os-release ] && . /etc/os-release
  [ "${ID:-}" = fedora ] && [ "${VERSION_ID:-0}" -ge 44 ] 2>/dev/null \
    || die "Fedora 44 or newer only (found ${PRETTY_NAME:-no /etc/os-release}): the first release that packages nix and nix-daemon. Elsewhere install Nix, then: nix run $ref#harness -- doctor"
  [ "$(id -u)" != 0 ] || die "run as your own user; sudo is used where root is needed"

  for p in nix nix-daemon bubblewrap socat tmux jq git-core policycoreutils-python-utils; do
    rpm -q "$p" >/dev/null 2>&1 || need+=("$p")
  done
  if [ ${#need[@]} -gt 0 ]; then
    printf '\n==> dnf install %s\n' "${need[*]}"
    if [ "$CHECK" = 1 ] || [ "$DRY" = 1 ]; then echo "    would run: sudo dnf install -y ${need[*]}"
    else sudo dnf install -y "${need[@]}"; fi
  fi
  if [ "$CHECK" = 1 ]; then echo; echo "install.sh --check: nothing changed; next would be: nix run $ref#harness -- bootstrap"; exit 0; fi

  # Fedora's profile.d/nix-daemon.sh only knows the legacy CA bundle paths.
  for f in /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt; do
    [ -n "${NIX_SSL_CERT_FILE:-}" ] || [ ! -r "$f" ] || export NIX_SSL_CERT_FILE="$f"
  done
  if ! command -v nix >/dev/null; then
    [ "$DRY" = 1 ] || die "nix not on PATH after the dnf step"
    echo; echo "install.sh --dry-run: next would be: nix run $ref#harness -- bootstrap $*"; exit 0
  fi
  export HARNESS_REF="$ref" HARNESS_ROOT_PACKAGES="${need[*]}"
  printf '\n==> nix run %s#harness -- bootstrap %s\n' "$ref" "$*"
  exec nix run "$ref#harness" -- bootstrap "$@"
}

main "$@"
