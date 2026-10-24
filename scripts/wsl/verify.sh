#!/bin/sh
# What a managed NixOS-WSL host should look like after install-wsl.ps1, run
# as the default user. Prints; does not judge beyond the last two lines.
#   wsl -d <distro> --cd <checkout>/scripts -- sh ./wsl/verify.sh
ok=0; bad=0
check() { # check <label> <command...>
  label="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok   $label"; ok=$((ok + 1)); else echo "FAIL $label"; bad=$((bad + 1)); fi
}

echo "== host"
printf '%s, ' "$(sed -n 's/^PRETTY_NAME="\(.*\)"/\1/p' /etc/os-release)"; uname -r
echo "user $(id -un) (uid $(id -u)), groups: $(id -Gn)"
echo "hostname $(hostname)"
grep -E '^(default|hostname|enabled|appendWindowsPath|generateResolvConf)=' /etc/wsl.conf 2>/dev/null | tr '\n' ' '; echo

echo "== network"
grep -v '^#' /etc/resolv.conf | head -n 2
check "DNS resolves github.com"            getent hosts github.com
check "HTTPS reaches cache.nixos.org"      curl -sSf -o /dev/null --max-time 20 https://cache.nixos.org/nix-cache-info

echo "== nix"
nix --version
check "flakes enabled"                     sh -c 'nix config show | grep -E "^experimental-features = .*flakes"'
check "devenv cache configured"            sh -c 'nix config show | grep -E "^substituters = .*devenv.cachix.org"'

echo "== harness"
check "/etc/nixos is a git checkout"       test -d /etc/nixos/.git
check "managed tree at /etc/claude-code"   test -r /etc/claude-code/managed-settings.json
check "strict network allowlist"           sh -c 'grep -q "\"strictAllowlist\": *true" /etc/claude-code/managed-settings.json'
check "managed hook executable"            test -x /etc/claude-code/hooks/env-guard.sh
check "user namespaces on"                 sh -c '[ "$(sysctl -n user.max_user_namespaces 2>/dev/null || echo 0)" -gt 0 ]'
for t in bwrap socat direnv devenv ccmux claude git; do check "$t on PATH" command -v "$t"; done
# Session variables come from home-manager's shell files, so ask a login shell.
check "HARNESS_EXPECT_MANAGED in a login shell" bash -lc '[ -n "${HARNESS_EXPECT_MANAGED:-}" ]'
check "direnv hook in a login shell"         bash -lc 'grep -qs "direnv hook" ~/.bashrc ~/.profile ~/.bash_profile'
check "Windows PATH not appended"          sh -c '! printf %s "$PATH" | tr ":" "\n" | grep -q "^/mnt/c/Program"'

echo "== systemd"
systemctl is-system-running 2>/dev/null || true
systemctl --failed --no-legend --no-pager 2>/dev/null | head -n 5

echo "== result: $ok ok, $bad failed"
[ "$bad" -eq 0 ]
