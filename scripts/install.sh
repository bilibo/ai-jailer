#!/usr/bin/env bash
#   scripts/install.sh [--check] [--no-init] [--workers <a,b,...>] [--worker <name>]
#                      [--owner <login>] [--owner-sudo nopasswd|password|none]
#                      [other aj bootstrap flags]
#   curl -fsSL https://raw.githubusercontent.com/bilibo/ai-jailer/main/scripts/install.sh | bash -s -- [flags]
#
# Run once on a Linux host: what has to happen before `nix run` works, then
# `aj bootstrap` for the rest, then, from a checkout, `aj init` on the
# checkout itself.
#   - Fedora 44 or newer (the first release that packages nix): `dnf
#     install`, the SELinux label for the daemon socket, and the socket,
#     which the package leaves disabled.
#   - Any other Linux: the nix-installer, downloaded to a file first so a
#     failed download runs nothing. It confirms on the terminal; --yes passes
#     --no-confirm and is required when piped into bash.
#   - NixOS: Nix is the system's, nothing is installed.
#
# --check prints the root steps, bootstrap's included, and changes nothing;
# --dry-run does the same and, when Nix already runs, hands over to
# bootstrap's --dry-run. --no-init skips the checkout's shell. Every other
# flag goes to bootstrap; --dry-run, --yes and --verbose go to init as well.
# The root steps done here reach bootstrap's receipt through
# AI_JAILER_ROOT_PACKAGES and AI_JAILER_ROOT_STEPS, so `aj reset` reverses
# them.
set -euo pipefail

INSTALLER_URL=https://artifacts.nixos.org/nix-installer
CHECK=0; DRY=0; YES=0; INIT=1; pending=0
need=(); done_steps=(); pass=(); init_flags=()
# Tests point these at scratch files.
os_release="${AI_JAILER_OS_RELEASE:-/etc/os-release}"
nixos_marker="${AI_JAILER_NIXOS_MARKER:-/etc/NIXOS}"
nix_conf="${AI_JAILER_NIX_CONF:-/etc/nix/nix.conf}"
nix_profile_sh="${AI_JAILER_NIX_PROFILE_SH:-/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh}"

die() { echo "install.sh: $*" >&2; exit 1; }
# root <command...>: through sudo; under --check and --dry-run only printed.
root() {
  if [ "$CHECK" = 1 ] || [ "$DRY" = 1 ]; then echo "    would run: sudo $*"; pending=1
  else sudo "$@"; fi
}

fedora_steps() {
  local p
  for p in nix nix-daemon bubblewrap socat tmux jq git-core policycoreutils-python-utils; do
    rpm -q "$p" >/dev/null 2>&1 || need+=("$p")
  done
  if [ ${#need[@]} -gt 0 ]; then
    printf '\n==> dnf install %s\n' "${need[*]}"
    root dnf install -y "${need[@]}"
  fi
  # /nix gets default_t without a policy, and systemd (init_t) may not create
  # a socket in a default_t directory ("Failed to create listening socket:
  # Permission denied", no AVC logged). var_run_t is /run's type and what
  # the Determinate installer's nix.fc gives the socket directory.
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

# NixOS: Nix and nix.conf are the system configuration's; bootstrap prints
# the nix.settings block where nix.conf lacks flakes or the devenv cache.
nixos_steps() {
  command -v nix >/dev/null 2>&1 || die "NixOS without nix on PATH: run this from a login shell"
  printf '\n==> NixOS: nix from the system configuration, no installer; %s is the system'"'"'s\n' "$nix_conf"
}

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

# worker_plan <ref>: the root commands `aj bootstrap` would run for the
# worker flags in $pass. Printed, never run: bootstrap owns them
# (root_steps in pkgs/aj/bootstrap.sh).
worker_plan() {
  local ref="$1" i c w owner="${USER:-$(id -un)}" mode=nopasswd tag="NOPASSWD: " prefix="${AI_JAILER_WORKER_PREFIX:-w-}"
  local -a workers=() names
  for ((i = 0; i < ${#pass[@]}; i++)); do
    case "${pass[i]}" in
      --workers|--worker) IFS=, read -r -a names <<<"${pass[i+1]:-}"; workers+=("${names[@]}") ;;
      --owner) owner="${pass[i+1]:-$owner}" ;;
      --owner-sudo) mode="${pass[i+1]:-$mode}" ;;
    esac
  done
  local nixos=0
  if [ -e "$nixos_marker" ] || [ "${ID:-}" = nixos ]; then nixos=1; mode=none; fi   # NixOS: no sudoers.d; the owner's own sudo
  printf '\n==> bootstrap'"'"'s root steps once Nix is there: the managed rules link%s\n' "$([ ${#workers[@]} -gt 0 ] && echo ", the worker users, linger$([ "$nixos" = 1 ] || echo ", the sudo rule")")"
  echo "    would run: sudo nix build $ref#managed --out-link /etc/claude-code   (#managed-wsl under WSL)"
  [ ${#workers[@]} -gt 0 ] || return 0
  echo "    would run: sudo groupadd agents   (unless the group exists)"
  for c in "${workers[@]}"; do
    w="$prefix$c"
    echo "    would run: sudo groupadd $w"
    echo "    would run: sudo useradd -m -g $w -G agents -s /bin/bash -c 'ai-jailer worker for $c' $w"
    echo "    would run: sudo chmod 0750 /home/$w"
    echo "    would run: sudo usermod -aG $w $owner"
    echo "    would run: sudo loginctl enable-linger $w"
  done
  if [ "$mode" != none ]; then
    [ "$mode" != password ] || tag=""
    echo "    would run: sudo install -m 0440 <new content> /etc/sudoers.d/ai-jailer   ($owner ALL=(%agents) ${tag}ALL)"
    echo "    would run: sudo visudo -cf /etc/sudoers.d/ai-jailer"
  fi
  for c in "${workers[@]}"; do
    echo "    would run: sudo -u $prefix$c -i nix run $ref#aj -- bootstrap --no-root --yes --jailer $ref"
  done
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

  # Run from a checkout, the checkout is the ref and gets its shell built at
  # the end; piped into bash, there is none.
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/../flake.nix" ]; then
    here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
  fi
  ref="${AI_JAILER_REF:-${here:+path:$here}}"; ref="${ref:-github:bilibo/ai-jailer}"

  # shellcheck disable=SC1090
  [ -r "$os_release" ] && . "$os_release"
  [ "$(id -u)" != 0 ] || die "run as your own user; sudo is used where root is needed"
  if [ -e "$nixos_marker" ] || [ "${ID:-}" = nixos ]; then nixos_steps
  elif [ "${ID:-}" = fedora ] && [ "${VERSION_ID:-0}" -ge 44 ] 2>/dev/null; then fedora_steps
  else installer_steps; fi
  [ "$CHECK" != 1 ] || worker_plan "$ref"
  if [ "$CHECK" = 1 ]; then echo; echo "install.sh --check: nothing changed; next would be: nix run $ref#aj -- bootstrap"; exit 0; fi

  # Nix-built tools look for the CA bundle at the NixOS and Debian paths or
  # where NIX_SSL_CERT_FILE points; Fedora keeps it elsewhere.
  for f in /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt; do
    [ -n "${NIX_SSL_CERT_FILE:-}" ] || [ ! -r "$f" ] || export NIX_SSL_CERT_FILE="$f"
  done
  # The nix-installer leaves flakes off; bootstrap writes them into nix.conf.
  export NIX_CONFIG="extra-experimental-features = nix-command flakes"
  if ! command -v nix >/dev/null || [ "$pending" = 1 ]; then
    [ "$DRY" = 1 ] || die "nix not on PATH after the install step"
    echo; echo "install.sh --dry-run: next would be: nix run $ref#aj -- bootstrap ${pass[*]}"; exit 0
  fi
  # Only in a real run: under --dry-run with nothing pending, the lists are empty.
  [ "$DRY" = 1 ] && done_steps=()
  export AI_JAILER_REF="$ref" AI_JAILER_ROOT_PACKAGES="${need[*]}" AI_JAILER_ROOT_STEPS="${done_steps[*]}"
  printf '\n==> nix run %s#aj -- bootstrap %s\n' "$ref" "${pass[*]}"
  # Bootstrap exits 1 when its report has a MISSING line; on a host that gets
  # tmux and claude from the checkout's shell that is expected before init
  # builds it, so init still runs. The exit code is kept so a real gap is
  # not hidden.
  local rc=0
  nix run "$ref#aj" -- bootstrap "${pass[@]}" || rc=$?
  if [ "$INIT" = 1 ] && [ -n "$here" ] && [ -e "$here/.envrc" ]; then
    [ "$rc" = 0 ] || echo "(bootstrap reported missing items; the checkout's shell may provide them, init runs anyway)"
    printf '\n==> nix run %s#aj -- init %s   (this checkout: its shell, then the checks on its settings file and hook)\n' "$ref" "$here"
    nix run "$ref#aj" -- init "$here" "${init_flags[@]}"
  fi
  return "$rc"
}

# One function, called on the last line: piped into bash, nothing runs before
# the whole script has arrived.
main "$@"
