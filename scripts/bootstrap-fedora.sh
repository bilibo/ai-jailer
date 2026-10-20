#!/usr/bin/env bash
#   scripts/bootstrap-fedora.sh [--check] [--no-root] [--no-profile] [--upgrade]
#                               [--trusted-user] [--code-root <dir>] [--harness <flakeref>]
#   scripts/bootstrap-fedora.sh --reset [--yes] [--no-root]
#
# Takes a Fedora host (44 or newer: Fedora packages Nix itself since 44) with
# Claude Code and VS Code already installed to the unmanaged-host shape of the
# README: Nix in multi-user mode from Fedora's own packages, direnv >= 2.38,
# devenv and ccmux from this flake (`nix profile add`, pinned by flake.lock),
# and the user-side configuration the home module would write on a managed
# host: direnv.toml, the tmux rules, the direnv hook, HARNESS_CODE_ROOT, the
# session PATH for GUI-launched VS Code, mkhl.direnv. No harness module and
# no managed settings: repos that import `harness/devenv` carry the rules
# (scripts/init-repo.sh sets one up).
#
# Idempotent: every step checks before it writes, so re-run it after a
# change. --upgrade also moves the three profile packages to the checkout's
# current flake.lock. Root is needed for dnf, /etc/nix/nix.conf and the
# nix-daemon socket; those steps go through sudo and say what they do first.
# --no-root skips them; --no-profile skips the `nix profile` step for a host
# that gets direnv, devenv and ccmux some other way (the README's "your own
# configuration"). --check changes nothing and reports every
# prerequisite; exit 1 when one the harness needs is missing. That is the
# host half of the runbook's verification section.
#
# --trusted-user adds you to Nix's trusted-users. Not needed: the devenv
# cache goes into the root-owned nix.conf as a substituter, which is what
# devenv checks for. A trusted user can pass any option to the daemon
# (unsigned paths, other caches, sandbox off), and agents run as you, so the
# default keeps that door shut.
#
# --reset reverses everything the script put on the host (the nix packages,
# /nix, /etc/nix, the SELinux rule, the build users, the nix profile and
# caches, the direnv allow database, every user file above, the VS Code
# pieces) so the next run is from zero. It asks before it starts unless
# --yes; it never touches the code root, so delete a test repo by hand.
# shellcheck disable=SC1091,SC2015,SC2088  # system files are not inputs; `x && ok || miss` reports, ok never fails; ~ in messages is text
set -euo pipefail

CHECK=0; NO_ROOT=0; NO_PROFILE=0; UPGRADE=0; TRUSTED_USER=0; RESET=0; YES=0
CODE_ROOT="${HARNESS_CODE_ROOT:-$HOME/code/git}"
HARNESS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
HARNESS_REF="path:$HARNESS_DIR"
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1 ;;
    --reset) RESET=1 ;;
    --yes) YES=1 ;;
    --no-root) NO_ROOT=1 ;;
    --no-profile) NO_PROFILE=1 ;;
    --upgrade) UPGRADE=1 ;;
    --trusted-user) TRUSTED_USER=1 ;;
    --code-root) CODE_ROOT="${2:?--code-root needs a directory}"; shift ;;
    --harness) HARNESS_REF="${2:?--harness needs a flake reference}"; shift ;;
    -h|--help) sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "bootstrap-fedora: unknown argument $1 (see --help)" >&2; exit 64 ;;
  esac
  shift
done
CODE_ROOT="${CODE_ROOT%/}"

MARK_BEGIN="# --- claude-nix-harness (scripts/bootstrap-fedora.sh) ---"
MARK_END="# --- end claude-nix-harness ---"
DEVENV_CACHE="https://devenv.cachix.org"
DEVENV_KEY="devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
MIN_CLAUDE="2.1.295"   # onFailure: block in hook registrations
MIN_DIRENV="2.38"      # require_allowed in .envrc
MIN_TMUX="3.2"         # extended-keys

# Nix-built tools (devenv's fetcher included) look for the CA bundle at the
# NixOS and Debian path, or where NIX_SSL_CERT_FILE points. Fedora 44 keeps
# it only here (the legacy /etc/pki/tls/certs/ca-bundle.crt and
# /etc/ssl/certs/ca-bundle.crt links are gone, which is also why Fedora's
# own profile.d/nix-daemon.sh fails to set the variable).
CA_BUNDLE=""
for f in /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt; do
  [ -r "$f" ] && { CA_BUNDLE="$f"; break; }
done

missing=0
ok()   { printf 'ok    %s\n' "$*"; }
miss() { printf 'MISSING %s\n' "$*"; missing=1; }
warn() { printf 'warn  %s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
die()  { echo "bootstrap-fedora: $*" >&2; exit 1; }
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }  # ver_ge <have> <want>

# Fedora's profile.d puts ~/.nix-profile/bin and the default profile on PATH
# for new shells; this shell may predate the dnf step.
nix_path() {
  unset __ETC_PROFILE_NIX_SOURCED
  [ -r /etc/profile.d/nix-daemon.sh ] && . /etc/profile.d/nix-daemon.sh
  [ -n "${NIX_SSL_CERT_FILE:-}" ] || [ -z "$CA_BUNDLE" ] || export NIX_SSL_CERT_FILE="$CA_BUNDLE"
  return 0
}

# ---------------------------------------------------------------- preflight
. /etc/os-release
[ "${ID:-}" = fedora ] || die "this script is for Fedora (found ${ID:-unknown}); the dnf step is the only distro-specific part"
[ "${VERSION_ID%%.*}" -ge 44 ] 2>/dev/null || die "Fedora 44 or newer needed: the first release that packages nix and nix-daemon"
[ "$(id -u)" != 0 ] || die "run as your own user; sudo is used where root is needed"

# ---------------------------------------------------------------- root steps
root_steps() {
  local pkgs=(nix nix-daemon bubblewrap socat tmux jq git-core policycoreutils-python-utils) need=() p
  for p in "${pkgs[@]}"; do rpm -q "$p" >/dev/null 2>&1 || need+=("$p"); done
  if [ ${#need[@]} -gt 0 ]; then
    step "dnf install ${need[*]}"
    sudo dnf install -y "${need[@]}"
  fi

  # Fedora's nix.conf already enables nix-command and flakes. The harness block
  # adds the devenv cache; trusted-users only on request (header).
  local conf=/etc/nix/nix.conf want tmp
  # Everything but a previous harness block, then the block.
  want=$(awk -v b="$MARK_BEGIN" -v e="$MARK_END" '$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$conf" 2>/dev/null || true)
  want="${want:+$want
}$MARK_BEGIN
extra-substituters = $DEVENV_CACHE
extra-trusted-public-keys = $DEVENV_KEY"
  [ "$TRUSTED_USER" = 1 ] && want="$want
trusted-users = root $USER"
  want="$want
$MARK_END"
  if [ "$(cat "$conf" 2>/dev/null)" != "$want" ]; then
    step "write $conf (harness block: devenv cache$([ "$TRUSTED_USER" = 1 ] && echo ", trusted-users"))"
    tmp=$(mktemp); printf '%s\n' "$want" >"$tmp"
    sudo install -m 0644 -o root -g root "$tmp" "$conf"; rm -f "$tmp"
    systemctl is-active -q nix-daemon.service && sudo systemctl restart nix-daemon.service
  fi

  # SELinux: /nix gets default_t without a policy, and systemd (init_t) may
  # not create a socket in a default_t directory ("Failed to create listening
  # socket: Permission denied", no AVC in the journal when auditd runs). The
  # Determinate installer's nix.fc labels the socket directory var_run_t, the
  # type /run has; same here, as a persistent file-context rule.
  if [ "$(getenforce 2>/dev/null)" != Disabled ] && ! matchpathcon -n /nix/var/nix/daemon-socket/socket 2>/dev/null | grep -q var_run_t; then
    step "SELinux: label /nix/var/nix/daemon-socket as var_run_t so systemd can create the daemon socket"
    sudo semanage fcontext -a -t var_run_t '/nix/var/nix/daemon-socket(/.*)?'
    sudo restorecon -RF /nix/var/nix/daemon-socket
  fi

  if ! systemctl is-enabled -q nix-daemon.socket 2>/dev/null || ! systemctl is-active -q nix-daemon.socket; then
    step "enable the nix-daemon socket"
    sudo systemctl enable --now nix-daemon.socket
  fi
}

# ---------------------------------------------------------------- user steps
profile_has() { # profile_has <name>
  nix profile list --json 2>/dev/null \
    | jq -e --arg n "$1" '.elements | if type == "object" then has($n) else map((.attrPath // "") | endswith("." + $n)) | any end' >/dev/null
}

profile_steps() {
  nix_path
  command -v nix >/dev/null || die "nix not on PATH after the dnf step"
  nix store info >/dev/null 2>&1 || nix store ping >/dev/null 2>&1 || die "the nix daemon does not answer (systemctl status nix-daemon.socket)"
  local sub=install name
  nix profile add --help >/dev/null 2>&1 && sub=add
  for name in direnv devenv ccmux; do
    if profile_has "$name"; then
      if [ "$UPGRADE" = 1 ]; then step "nix profile upgrade $name"; nix profile upgrade "$name"; fi
    else
      step "nix profile $sub $HARNESS_REF#$name"
      [ "$name" = direnv ] && echo "    (direnv builds from source while nixpkgs ships < $MIN_DIRENV; a few minutes once)"
      nix profile "$sub" "$HARNESS_REF#$name"
    fi
  done
}

write_if_differs() { # write_if_differs <path> <content>
  if [ ! -e "$1" ] || [ "$(cat "$1")" != "$2" ]; then
    step "write $1"; mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" >"$1"
  fi
}

user_steps() {
  # direnv: the home module's programs.direnv.config.global.
  local f="$HOME/.config/direnv/direnv.toml"
  local direnv_toml="$MARK_BEGIN
[global]
strict_env = true
# devenv evaluations are slow; the default 5s warning is noise.
warn_timeout = \"2m\"
# .env files hold credentials.
load_dotenv = false
# No whitelist.prefix entries, ever: path-only, never re-prompts."
  if [ -e "$f" ] && ! grep -q -F "$MARK_BEGIN" "$f"; then
    warn "$f exists and is not the harness one; merge by hand: strict_env, warn_timeout = \"2m\", load_dotenv = false, no whitelist"
  else
    write_if_differs "$f" "$direnv_toml"
  fi

  # tmux: the home module's programs.tmux.extraConfig, appended once.
  f="$HOME/.config/tmux/tmux.conf"
  if ! grep -q -F "$MARK_BEGIN" "$f" 2>/dev/null; then
    step "append the harness block to $f"
    mkdir -p "$(dirname "$f")"
    cat >>"$f" <<TMUX
$MARK_BEGIN
# The tmux server keeps the first client's environment. Refresh these on
# attach and never seed them into new panes, so a pane opened from customer
# A's shell never carries A's direnv state into customer B.
set -ga update-environment "DIRENV_DIR DIRENV_DIFF DIRENV_WATCHES DIRENV_FILE"
set-environment -gu DIRENV_DIR
set-environment -gu DIRENV_DIFF
set-environment -gu DIRENV_WATCHES
set-environment -gu DIRENV_FILE
# Claude Code's TUI: shift+enter and other chords need extended keys, focus
# events keep its redraws right, passthrough lets it talk to the outer
# terminal (clipboard, images).
set -g extended-keys on
set -g focus-events on
set -g allow-passthrough on
$MARK_END
TMUX
  fi

  # bash: the direnv hook and the code root (home.sessionVariables). Fedora's
  # ~/.bashrc sources ~/.bashrc.d/* after /etc/bashrc has run profile.d, so
  # the nix profile is already on PATH here. No HARNESS_EXPECT_MANAGED: this
  # host has no managed settings by design.
  local root_expr="$CODE_ROOT"
  [[ "$root_expr" == "$HOME/"* ]] && root_expr="\$HOME/${root_expr#"$HOME/"}"
  write_if_differs "$HOME/.bashrc.d/claude-nix-harness.sh" "$MARK_BEGIN
export HARNESS_CODE_ROOT=\"$root_expr\"
# Fedora's own profile.d/nix-daemon.sh only knows the legacy bundle paths.
[ -n \"\${NIX_SSL_CERT_FILE:-}\" ] || export NIX_SSL_CERT_FILE=\"${CA_BUNDLE:-/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem}\"
if command -v direnv >/dev/null 2>&1; then eval \"\$(direnv hook bash)\"; fi"

  # GUI session PATH: VS Code launched from the menu (and the claude it spawns)
  # otherwise never sees the nix profile. systemd user environment generator;
  # takes effect at the next login.
  write_if_differs "$HOME/.config/environment.d/50-claude-nix-harness.conf" "$MARK_BEGIN
PATH=\$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:\$HOME/.local/bin:\$PATH
NIX_SSL_CERT_FILE=${CA_BUNDLE:-/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem}"

  [ -d "$CODE_ROOT" ] || { step "mkdir $CODE_ROOT"; mkdir -p "$CODE_ROOT"; }

  # VS Code: mkhl.direnv loads the devenv shell into the window (runbook,
  # daily flow); direnv.path makes it work before the next login too.
  if command -v code >/dev/null 2>&1; then
    if ! code --list-extensions 2>/dev/null | grep -q -i -x 'mkhl.direnv'; then
      step "code --install-extension mkhl.direnv"
      code --install-extension mkhl.direnv >/dev/null
    fi
    local vs="$HOME/.config/Code/User/settings.json" direnv_bin
    nix_path; direnv_bin=$(command -v direnv 2>/dev/null || echo "$HOME/.nix-profile/bin/direnv")
    if command -v jq >/dev/null && ! jq -e --arg p "$direnv_bin" --arg c "$CA_BUNDLE" \
         '.["direnv.path.executable"] == $p and .["direnv.extraEnv"].NIX_SSL_CERT_FILE == $c' "$vs" >/dev/null 2>&1; then
      step "set direnv.path.executable and direnv.extraEnv.NIX_SSL_CERT_FILE in $vs"
      mkdir -p "$(dirname "$vs")"; [ -s "$vs" ] || echo '{}' >"$vs"
      local tmp; tmp=$(mktemp)
      jq --arg p "$direnv_bin" --arg c "$CA_BUNDLE" \
        '. + {"direnv.path.executable": $p} | .["direnv.extraEnv"] = ((.["direnv.extraEnv"] // {}) + {NIX_SSL_CERT_FILE: $c})' "$vs" >"$tmp" && mv "$tmp" "$vs"
    fi
  fi
}

# ---------------------------------------------------------------- reset
# strip_block <file>: the file without the harness block; removes the file
# when nothing else is left.
strip_block() {
  local f="$1" rest
  [ -e "$f" ] || return 0
  grep -q -F "$MARK_BEGIN" "$f" || return 0
  rest=$(awk -v b="$MARK_BEGIN" -v e="$MARK_END" '$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$f")
  if [ -z "$(printf '%s' "$rest" | tr -d '[:space:]')" ]; then step "remove $f"; rm -f "$f"
  else step "remove the harness block from $f"; printf '%s\n' "$rest" >"$f"; fi
}

reset_steps() {
  local nixpkgs=(nix nix-daemon nix-legacy nix-core nix-libs nix-system nix-filesystem) i
  cat <<PLAN
This removes, on this host:
  root:  nix-daemon.socket, the packages ${nixpkgs[*]} (and the dependencies
         dnf pulled in with them), /nix and /etc/nix, the SELinux rule for
         the daemon socket, the nixbld build users
  user:  the nix profile and state (~/.nix-profile, ~/.local/state/nix),
         ~/.cache/nix, ~/.cache/devenv, the direnv allow database
         (~/.local/share/direnv), the harness parts of direnv.toml, tmux.conf,
         ~/.bashrc.d, environment.d, the mkhl.direnv extension and its settings
Not touched: $CODE_ROOT (delete a test repo by hand), Claude Code's own files.
PLAN
  if [ "$YES" != 1 ]; then
    printf "Type 'reset' to continue: "; read -r answer; [ "$answer" = reset ] || die "aborted"
  fi

  if [ "$NO_ROOT" != 1 ]; then
    sudo -v || die "sudo is needed for the root part (or pass --no-root)"
    step "disable the nix daemon"
    sudo systemctl disable --now nix-daemon.socket nix-daemon.service 2>/dev/null || true
    local installed=() p
    for p in "${nixpkgs[@]}"; do rpm -q "$p" >/dev/null 2>&1 && installed+=("$p"); done
    if [ ${#installed[@]} -gt 0 ]; then step "dnf remove ${installed[*]}"; sudo dnf remove -y "${installed[@]}"; fi
    step "remove /nix and /etc/nix"
    sudo rm -rf /nix /etc/nix
    if [ "$(getenforce 2>/dev/null)" != Disabled ]; then
      step "remove the SELinux rule for the daemon socket"
      sudo semanage fcontext -d '/nix/var/nix/daemon-socket(/.*)?' 2>/dev/null || true
    fi
    step "remove the nixbld build users"
    for i in $(seq 1 10); do sudo userdel "nixbld-$i" 2>/dev/null || true; done
    sudo groupdel nixbld 2>/dev/null || true
  fi

  step "remove the nix profile, caches and the direnv allow database"
  rm -rf "$HOME/.nix-profile" "$HOME/.nix-defexpr" "$HOME/.nix-channels" "$HOME/.local/state/nix" \
         "$HOME/.cache/nix" "$HOME/.cache/devenv" "$HOME/.local/share/devenv" "$HOME/.local/share/direnv"
  local f="$HOME/.config/direnv/direnv.toml"
  if grep -q -F "$MARK_BEGIN" "$f" 2>/dev/null; then step "remove $f"; rm -f "$f"; fi
  strip_block "$HOME/.config/tmux/tmux.conf"
  for f in "$HOME/.bashrc.d/claude-nix-harness.sh" "$HOME/.config/environment.d/50-claude-nix-harness.conf"; do
    [ -e "$f" ] && { step "remove $f"; rm -f "$f"; }
  done
  if command -v code >/dev/null 2>&1; then
    if code --list-extensions 2>/dev/null | grep -q -i -x 'mkhl.direnv'; then
      step "code --uninstall-extension mkhl.direnv"; code --uninstall-extension mkhl.direnv >/dev/null 2>&1 || true
    fi
    local vs="$HOME/.config/Code/User/settings.json" tmp
    if [ -s "$vs" ] && command -v jq >/dev/null && jq -e 'has("direnv.path.executable") or has("direnv.extraEnv")' "$vs" >/dev/null 2>&1; then
      step "remove the direnv settings from $vs"
      tmp=$(mktemp)
      jq 'del(.["direnv.path.executable"])
          | if (.["direnv.extraEnv"] | type) == "object" then .["direnv.extraEnv"] |= del(.NIX_SSL_CERT_FILE) else . end
          | if .["direnv.extraEnv"] == {} then del(.["direnv.extraEnv"]) else . end' "$vs" >"$tmp" && mv "$tmp" "$vs"
    fi
  fi
  cat <<NEXT

Reset done. From zero again: open a new terminal (this one still has the old
PATH), delete a test repo if you want init-repo.sh from scratch, e.g.
  rm -rf $CODE_ROOT/raul/harness-test
then $HARNESS_DIR/scripts/bootstrap-fedora.sh and the rest of the runbook's
"From zero" list. Log out and in once at the end for GUI-launched VS Code.
NEXT
}

# ---------------------------------------------------------------- report
report() {
  nix_path
  local v
  echo "host: Fedora ${VERSION_ID} ($(uname -m)), SELinux $(getenforce 2>/dev/null || echo unknown)"

  if command -v nix >/dev/null 2>&1; then
    v=$(nix --version | awk '{print $NF}')
    if nix store info >/dev/null 2>&1 || nix store ping >/dev/null 2>&1; then ok "nix $v, daemon answers"; else miss "nix $v installed but the daemon does not answer (systemctl enable --now nix-daemon.socket)"; fi
    grep -q -E '^experimental-features.*flakes' /etc/nix/nix.conf 2>/dev/null && ok "flakes enabled in /etc/nix/nix.conf" || miss "flakes not enabled in /etc/nix/nix.conf"
    grep -q -F "$DEVENV_CACHE" /etc/nix/nix.conf 2>/dev/null && ok "devenv cache in /etc/nix/nix.conf" || warn "devenv cache not in /etc/nix/nix.conf: devenv builds more from source"
    if [ "$(getenforce 2>/dev/null)" != Disabled ]; then
      if matchpathcon -n /nix/var/nix/daemon-socket/socket 2>/dev/null | grep -q var_run_t; then ok "SELinux: daemon socket directory labeled var_run_t"
      else miss "SELinux: daemon socket directory labeled $(matchpathcon -n /nix/var/nix/daemon-socket/socket 2>/dev/null), systemd cannot create the socket (sudo semanage fcontext -a -t var_run_t '/nix/var/nix/daemon-socket(/.*)?'; sudo restorecon -RF /nix/var/nix/daemon-socket)"; fi
      if systemctl is-active -q auditd 2>/dev/null; then warn "SELinux denials go to auditd, not the journal: sudo ausearch -m avc -ts recent | grep nix"
      elif journalctl -q -b -g 'avc.*(nix|/nix/)' --no-pager 2>/dev/null | grep -q .; then warn "SELinux denials mentioning nix in this boot's journal: journalctl -b -g avc"
      else ok "no SELinux denials mentioning nix in this boot's journal"; fi
    fi
  else
    miss "nix (dnf install nix nix-daemon)"
  fi

  if [ -n "$CA_BUNDLE" ]; then ok "CA bundle for Nix-built tools: $CA_BUNDLE (NIX_SSL_CERT_FILE)"; else miss "no CA bundle found for NIX_SSL_CERT_FILE: devenv cannot fetch over https"; fi
  if command -v direnv >/dev/null 2>&1; then
    v=$(direnv version); ver_ge "$v" "$MIN_DIRENV" && ok "direnv $v ($(command -v direnv))" || miss "direnv $v is older than $MIN_DIRENV (require_allowed): nix profile add $HARNESS_REF#direnv"
  else miss "direnv >= $MIN_DIRENV (nix profile add $HARNESS_REF#direnv)"; fi
  if command -v devenv >/dev/null 2>&1; then ok "devenv $(devenv version 2>/dev/null | awk '{print $NF}') ($(command -v devenv))"; else miss "devenv (nix profile add $HARNESS_REF#devenv)"; fi
  if command -v ccmux >/dev/null 2>&1; then ok "ccmux ($(command -v ccmux))"; else warn "ccmux not on the host PATH (the devenv shell of a harness repo has it; nix profile add $HARNESS_REF#ccmux for everywhere)"; fi

  for t in bwrap socat; do command -v "$t" >/dev/null 2>&1 && ok "$t ($(command -v "$t"))" || miss "$t (dnf install bubblewrap socat): the sandbox refuses to start without it"; done
  v=$(cat /proc/sys/user/max_user_namespaces 2>/dev/null || echo 0)
  [ "$v" -gt 0 ] && ok "user namespaces enabled (max $v)" || miss "user namespaces disabled: bubblewrap cannot run"
  if bwrap --ro-bind / / --dev /dev --proc /proc --unshare-all --die-with-parent -- /bin/true 2>/dev/null; then ok "bubblewrap works under this SELinux mode"; else miss "bubblewrap cannot create a sandbox here"; fi
  if command -v tmux >/dev/null 2>&1; then v=$(tmux -V | awk '{print $2}'); ver_ge "${v//[a-z]/}" "$MIN_TMUX" && ok "tmux $v" || warn "tmux $v is older than $MIN_TMUX (extended-keys)"; else miss "tmux (dnf install tmux)"; fi
  command -v jq >/dev/null 2>&1 && ok "jq" || miss "jq (dnf install jq)"
  command -v git >/dev/null 2>&1 && ok "git $(git --version | awk '{print $3}')" || miss "git (dnf install git-core)"

  if command -v claude >/dev/null 2>&1; then
    v=$(claude --version 2>/dev/null | awk '{print $1}')
    ver_ge "$v" "$MIN_CLAUDE" && ok "claude $v ($(command -v claude), autoUpdates=$(jq -r 'if has("autoUpdates") then .autoUpdates else "default" end' "$HOME/.claude.json" 2>/dev/null))" || miss "claude $v is older than $MIN_CLAUDE (onFailure: block)"
  else miss "claude: install Claude Code first (the native installer puts it in ~/.local/bin)"; fi
  [ -r /etc/claude-code/managed-settings.json ] && warn "/etc/claude-code/managed-settings.json exists: this host carries managed settings, the script assumed none" || ok "no managed settings (unmanaged host: the repo file is the whole harness)"

  if command -v code >/dev/null 2>&1; then
    ok "code $(code --version 2>/dev/null | head -1)"
    code --list-extensions 2>/dev/null | grep -q -i -x 'anthropic.claude-code' && ok "VS Code extension anthropic.claude-code" || warn "VS Code extension anthropic.claude-code not installed"
    code --list-extensions 2>/dev/null | grep -q -i -x 'mkhl.direnv' && ok "VS Code extension mkhl.direnv" || miss "VS Code extension mkhl.direnv (code --install-extension mkhl.direnv)"
  else warn "code not on PATH: VS Code steps skipped"; fi

  [ -d "$CODE_ROOT" ] && ok "code root $CODE_ROOT" || miss "code root $CODE_ROOT (ccmux resolves <customer>/<repo> under it)"
  if grep -q -F "$MARK_BEGIN" "$HOME/.config/direnv/direnv.toml" 2>/dev/null; then ok "direnv.toml"
  elif [ -e "$HOME/.config/direnv/direnv.toml" ]; then warn "~/.config/direnv/direnv.toml exists and is not the harness one (strict_env, warn_timeout, load_dotenv = false)"
  else miss "~/.config/direnv/direnv.toml"; fi
  grep -q -F "$MARK_BEGIN" "$HOME/.config/tmux/tmux.conf" 2>/dev/null && ok "tmux.conf harness block" || miss "tmux.conf harness block"
  grep -q 'direnv hook bash' "$HOME/.bashrc.d/claude-nix-harness.sh" 2>/dev/null && ok "direnv hook and HARNESS_CODE_ROOT in ~/.bashrc.d" || miss "~/.bashrc.d/claude-nix-harness.sh"
  [ -r "$HOME/.config/environment.d/50-claude-nix-harness.conf" ] && ok "session PATH (environment.d; next login)" || warn "no environment.d PATH entry: GUI-launched VS Code will not see the nix profile"
  [ -n "${HARNESS_EXPECT_MANAGED:-}" ] && warn "HARNESS_EXPECT_MANAGED is set but this host has no managed settings" || true
}

if [ "$RESET" = 1 ]; then
  reset_steps; exit 0
elif [ "$CHECK" = 1 ]; then
  report
else
  [ "$NO_ROOT" = 1 ] || { sudo -v || die "sudo is needed for dnf, /etc/nix/nix.conf and the nix-daemon socket (or pass --no-root after doing those by hand)"; root_steps; }
  [ "$NO_PROFILE" = 1 ] || profile_steps
  user_steps
  echo
  report
  cat <<NEXT

Next: open a new terminal (PATH and NIX_SSL_CERT_FILE come from profile.d and ~/.bashrc.d), then
  $HARNESS_DIR/scripts/init-repo.sh <customer>/<repo>     # a harness repo under $CODE_ROOT
  $HARNESS_DIR/scripts/live-check.sh $CODE_ROOT/<customer>/<repo>
Log out and in once so GUI-launched VS Code gets the nix profile on PATH.
NEXT
fi
[ "$missing" = 0 ]
