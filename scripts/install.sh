#!/usr/bin/env bash
#   scripts/install.sh [--check] [--no-init] [harness bootstrap flags]
#   curl -fsSL https://raw.githubusercontent.com/bilibo/claude-nix-harness/main/scripts/install.sh | bash -s -- [flags]
#
# The one install route, run once on a plain Linux host: what has to happen
# before `nix run` works, then `harness bootstrap` for the rest, then, from a
# checkout, `harness init` on the checkout itself (its shell built, its
# settings file and hook checked), so `git clone`, `scripts/install.sh`,
# `ccmux` is the whole sequence.
#
# Fedora 44 or newer (the first release that packages nix and nix-daemon):
# `dnf install` of nix, nix-daemon and what the sandbox and the harness
# call, the SELinux label systemd needs to create the daemon socket in /nix,
# and the socket itself, which the nix-daemon package leaves disabled. Any
# other Linux: the nix-installer served at artifacts.nixos.org (multi-user
# daemon; its uninstaller stays at /nix/nix-installer, which `harness reset`
# runs), downloaded to a file first so a failed download runs nothing. The
# installer asks for sudo itself and confirms on the terminal; --yes passes
# --no-confirm, and is required when the script is piped into bash with no
# terminal. That installer leaves flakes off, so the script turns them on for
# its own nix calls and bootstrap writes them into nix.conf. The kernel's
# user-namespace restriction (Ubuntu 23.10 and later) is bootstrap's: it
# offers the sysctl and can be declined. NixOS (/etc/NIXOS, or ID=nixos in
# os-release): Nix is the system's, nothing is downloaded, and nix.conf is a
# store symlink the system configuration owns, so the nix.settings block it
# needs is printed for configuration.nix; bootstrap does the user side.
#
# The harness ref (`nix run`, and what bootstrap puts in the profile):
# HARNESS_REF, else this checkout when the script runs from one
# (path:<checkout>), else the published repo. What was done here reaches
# bootstrap's receipt through HARNESS_ROOT_PACKAGES and HARNESS_ROOT_STEPS,
# so `harness reset` reverses it. --check reports the root steps and changes
# nothing; --dry-run does the same, then hands over to bootstrap's --dry-run
# when Nix can already run. --no-init skips the checkout's shell. Every other
# flag goes to bootstrap (--dry-run, --yes and --verbose to init as well).
set -euo pipefail

INSTALLER_URL=https://artifacts.nixos.org/nix-installer
CHECK=0; DRY=0; YES=0; INIT=1; pending=0
need=(); done_steps=(); pass=(); init_flags=()
# Tests point these at scratch files.
os_release="${HARNESS_OS_RELEASE:-/etc/os-release}"
nixos_marker="${HARNESS_NIXOS_MARKER:-/etc/NIXOS}"
nix_conf="${HARNESS_NIX_CONF:-/etc/nix/nix.conf}"
nix_profile_sh="${HARNESS_NIX_PROFILE_SH:-/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh}"

die() { echo "install.sh: $*" >&2; exit 1; }
# root <command...>: through sudo; under --check and --dry-run only printed.
root() {
  if [ "$CHECK" = 1 ] || [ "$DRY" = 1 ]; then echo "    would run: sudo $*"; pending=1
  else sudo "$@"; fi
}

# Fedora: the packages, the SELinux label, the socket.
fedora_steps() {
  local p
  for p in nix nix-daemon bubblewrap socat tmux jq git-core policycoreutils-python-utils; do
    rpm -q "$p" >/dev/null 2>&1 || need+=("$p")
  done
  if [ ${#need[@]} -gt 0 ]; then
    printf '\n==> dnf install %s\n' "${need[*]}"
    root dnf install -y "${need[@]}"
  fi
  # SELinux: /nix gets default_t without a policy, and systemd (init_t) may
  # not create a socket in a default_t directory ("Failed to create listening
  # socket: Permission denied", no AVC in the journal when auditd runs). The
  # Determinate installer's nix.fc labels the socket directory var_run_t, the
  # type /run has; same here, as a persistent file-context rule.
  if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce 2>/dev/null)" != Disabled ] \
     && ! matchpathcon -n /nix/var/nix/daemon-socket/socket 2>/dev/null | grep -q var_run_t; then
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
}

# NixOS: Nix and nix.conf are the system configuration's. The block is
# printed where nix.conf lacks it (bootstrap prints the same one).
nixos_steps() {
  command -v nix >/dev/null 2>&1 || die "NixOS without nix on PATH: run this from a login shell"
  printf '\n==> NixOS: nix from the system configuration, no installer; %s is the system'"'"'s\n' "$nix_conf"
  if ! grep -q -E '^experimental-features.*flakes' "$nix_conf" 2>/dev/null || ! grep -q -F devenv.cachix.org "$nix_conf" 2>/dev/null; then
    cat <<'NIX'
    flakes and the devenv cache are not both in it; add to configuration.nix and rebuild:
      nix.settings = {
        experimental-features = [ "nix-command" "flakes" ];
        substituters = [ "https://devenv.cachix.org" ];
        trusted-public-keys = [ "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=" ];
      };
NIX
  fi
}

# Everything else: the nix-installer, only when there is no nix yet.
installer_steps() {
  local installer confirm=""
  command -v nix >/dev/null 2>&1 && return 0
  command -v curl >/dev/null 2>&1 || die "curl is needed to fetch the nix-installer"
  [ "$YES" != 1 ] || confirm=" --no-confirm"
  printf '\n==> install Nix with the nix-installer (%s): multi-user daemon, uninstaller at /nix/nix-installer; it asks for sudo itself\n' "$INSTALLER_URL"
  if [ "$CHECK" = 1 ] || [ "$DRY" = 1 ]; then echo "    would run: curl -sSfL $INSTALLER_URL -o <file> && sh <file> install$confirm"; pending=1; return 0; fi
  installer=$(mktemp)
  curl -sSfL "$INSTALLER_URL" -o "$installer"
  if [ -n "$confirm" ]; then sh "$installer" install --no-confirm
  elif { : </dev/tty; } 2>/dev/null; then sh "$installer" install </dev/tty
  else rm -f "$installer"; die "no terminal for the installer's confirmation: run with --yes (it passes --no-confirm)"; fi
  rm -f "$installer"
  # The installer edits the shell rc files; this shell has not read them.
  # shellcheck disable=SC1090
  [ -r "$nix_profile_sh" ] && . "$nix_profile_sh"
  command -v nix >/dev/null 2>&1 || die "Nix is installed but not on this shell's PATH yet: open a new terminal and run this again"
  done_steps+=(nix-installer)
}

main() {
  local a f here="" ref
  for a in "$@"; do
    case "$a" in
      --check) CHECK=1; continue ;;
      --no-init) INIT=0; continue ;;
      --dry-run) DRY=1; init_flags+=("$a") ;;
      --yes) YES=1; init_flags+=("$a") ;;
      --verbose) init_flags+=("$a") ;;
    esac
    pass+=("$a")
  done

  # Run from a checkout (scripts/install.sh next to flake.nix), the checkout
  # is the ref and gets its shell built at the end; piped into bash, there is
  # none.
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/../flake.nix" ]; then
    here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
  fi
  ref="${HARNESS_REF:-${here:+path:$here}}"; ref="${ref:-github:bilibo/claude-nix-harness}"

  # shellcheck disable=SC1090
  [ -r "$os_release" ] && . "$os_release"
  [ "$(id -u)" != 0 ] || die "run as your own user; sudo is used where root is needed"
  if [ -e "$nixos_marker" ] || [ "${ID:-}" = nixos ]; then nixos_steps
  elif [ "${ID:-}" = fedora ] && [ "${VERSION_ID:-0}" -ge 44 ] 2>/dev/null; then fedora_steps
  else installer_steps; fi
  if [ "$CHECK" = 1 ]; then echo; echo "install.sh --check: nothing changed; next would be: nix run $ref#harness -- bootstrap"; exit 0; fi

  # Nix-built tools look for the CA bundle at the NixOS and Debian paths or
  # where NIX_SSL_CERT_FILE points; Fedora keeps it elsewhere.
  for f in /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt; do
    [ -n "${NIX_SSL_CERT_FILE:-}" ] || [ ! -r "$f" ] || export NIX_SSL_CERT_FILE="$f"
  done
  # The nix-installer leaves flakes off; bootstrap writes them into nix.conf.
  export NIX_CONFIG="extra-experimental-features = nix-command flakes"
  if ! command -v nix >/dev/null || [ "$pending" = 1 ]; then
    [ "$DRY" = 1 ] || die "nix not on PATH after the install step"
    echo; echo "install.sh --dry-run: next would be: nix run $ref#harness -- bootstrap ${pass[*]}"; exit 0
  fi
  # Only in a real run: under --dry-run with nothing pending, the lists are empty.
  [ "$DRY" = 1 ] && done_steps=()
  export HARNESS_REF="$ref" HARNESS_ROOT_PACKAGES="${need[*]}" HARNESS_ROOT_STEPS="${done_steps[*]}"
  printf '\n==> nix run %s#harness -- bootstrap %s\n' "$ref" "${pass[*]}"
  # Bootstrap exits 1 when its report has a MISSING line. On a host that
  # gets tmux and claude from the checkout's shell that is the expected
  # state before init builds it (Ubuntu, 2026-10-21), so init still runs;
  # the exit code is kept so a real gap is not hidden.
  local rc=0
  nix run "$ref#harness" -- bootstrap "${pass[@]}" || rc=$?
  if [ "$INIT" = 1 ] && [ -n "$here" ] && [ -e "$here/.envrc" ]; then
    [ "$rc" = 0 ] || echo "(bootstrap reported missing items; the checkout's shell may provide them, init runs anyway)"
    printf '\n==> nix run %s#harness -- init %s   (this checkout: its shell, then the checks on its settings file and hook)\n' "$ref" "$here"
    nix run "$ref#harness" -- init "$here" "${init_flags[@]}"
  fi
  return "$rc"
}

# One function, called on the last line: piped into bash, nothing runs before
# the whole script has arrived.
main "$@"
