#!/bin/sh
# First install of a NixOS-WSL harness host, run as root by install-wsl.ps1:
#   sh ./wsl/bootstrap.sh <host-repo: git URL | /mnt/... folder> <output> [--switch|--no-switch]
#
# /etc/nixos becomes a git checkout of the host configuration, owned by the
# image's default user (uid 1000; the host flake may rename that user, the
# uid stays). The system is built as that user, because Nix refuses to open
# a git checkout owned by someone else, and activated as root. A folder
# without .git gets a local repository with one baseline commit, so the
# flake sees every file (a git flake reads only what is committed).
#
# After this the box is pull-only (wsl/update.sh); nothing here commits again.
set -eu

SRC="${1:?host repo (git URL or /mnt path)}"
OUT="${2:?nixosConfigurations attribute}"
SWITCH=1
[ "${3:-}" = "--no-switch" ] && SWITCH=0

REPO=/etc/nixos
OWNER_UID=1000
OWNER="$(getent passwd "$OWNER_UID" | cut -d: -f1)"
[ -n "$OWNER" ] || { echo "no user with uid $OWNER_UID" >&2; exit 2; }
export NIX_CONFIG="experimental-features = nix-command flakes"

# git is not in the NixOS-WSL image; until the host configuration brings
# it, `nix shell` lends one (fetches nixpkgs once).
if command -v git >/dev/null 2>&1; then GIT=git; else GIT="nix shell nixpkgs#git -c git"; fi
as_owner() { runuser -u "$OWNER" -- env NIX_CONFIG="$NIX_CONFIG" "$@"; }
og() { as_owner $GIT -C "$REPO" "$@"; }

if [ -d "$REPO/.git" ]; then
  echo "$REPO is already a git checkout; use wsl/update.sh" >&2
  exit 2
fi

echo "== bootstrap: $SRC -> $REPO  (#$OUT, owner $OWNER, uid $OWNER_UID)"
head -n 2 /etc/os-release

# Keep the image's configuration once, outside the repo.
if [ -f "$REPO/configuration.nix" ] && [ ! -f /root/configuration.nix.orig ]; then
  cp "$REPO/configuration.nix" /root/configuration.nix.orig
fi
mkdir -p "$REPO"
find "$REPO" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

case "$SRC" in
  /*)
    [ -f "$SRC/flake.nix" ] || { echo "$SRC has no flake.nix" >&2; exit 2; }
    echo "== copy $SRC (logs/ and result excluded)"
    (cd "$SRC" && tar --exclude=./logs --exclude=./result -cf - .) | (cd "$REPO" && tar -xf -)
    ;;
  *)
    echo "== git clone $SRC"
    $GIT clone -q "$SRC" "$REPO"
    ;;
esac
chmod -R u=rwX,go=rX "$REPO"
chown -R "$OWNER_UID:users" "$REPO"

if [ -d "$REPO/.git" ]; then
  echo "== checkout: $(og remote get-url origin 2>/dev/null || echo 'no remote')"
else
  echo "== git init + baseline commit"
  og init -q -b main
  og add -A
  og -c user.name="$OWNER" -c user.email="$OWNER@nixos-wsl" commit -q \
    -m "Baseline from install-wsl.ps1"
  echo "   no remote yet; add one with:"
  echo "     git -C $REPO remote add origin <url> && git -C $REPO push -u origin main"
fi
og log --oneline -n 3

echo "== build #$OUT as $OWNER"
LOG=/tmp/nixos-build.log
if ! T=$(as_owner nix build "$REPO#nixosConfigurations.$OUT.config.system.build.toplevel" \
          --no-link --print-out-paths --no-write-lock-file 2> "$LOG"); then
  grep -v '^copying path' "$LOG" | tail -n 60
  echo "== build FAILED (full log: $LOG)" >&2
  exit 1
fi
echo "$T"

if [ "$SWITCH" -eq 1 ]; then
  echo "== activate"
  nix-env -p /nix/var/nix/profiles/system --set "$T"
  "$T/bin/switch-to-configuration" switch 2>&1 | tail -n 40
else
  echo "== built, not activated. To switch:"
  echo "   sudo nix-env -p /nix/var/nix/profiles/system --set $T"
  echo "   sudo $T/bin/switch-to-configuration switch"
  echo "   then from Windows: wsl -t <distro>"
fi
echo "== current system"
readlink /run/current-system
echo "== git status (should be clean)"
og status --short
