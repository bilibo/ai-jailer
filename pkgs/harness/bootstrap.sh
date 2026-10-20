#!/usr/bin/env bash
#   harness bootstrap [--no-root] [--no-profile] [--trusted-user] [--no-account-sync]
#                     [--code-root <dir>] [--harness <flakeref>]
#   harness upgrade   [the bootstrap flags]
#   harness doctor    [--code-root <dir>]
#   harness reset     [--no-root]
#   each also takes --dry-run, --yes, --verbose
#
# Takes a Fedora host (44 or newer: Fedora packages Nix itself since 44) with
# Claude Code and VS Code already installed to the unmanaged-host shape of the
# README: Nix in multi-user mode from Fedora's own packages, direnv >= 2.38,
# devenv, ccmux and harness from this flake (`nix profile add`, pinned by
# flake.lock), and the user-side configuration the home module would write on
# a managed host: direnv.toml, the tmux rules, the direnv hook,
# HARNESS_CODE_ROOT, the session PATH for GUI-launched VS Code, mkhl.direnv.
# No harness module and no managed settings: repos that import
# `harness/devenv` carry the rules (`harness init` sets one up).
# scripts/install.sh does the root steps before Nix exists, then runs
# `harness bootstrap --no-root`.
#
# Idempotent: every step checks before it writes, so re-run it after a
# change. `upgrade` is bootstrap that also moves the profile packages to the
# harness ref's current flake.lock. Root is needed for dnf, /etc/nix/nix.conf
# and the nix-daemon socket; those steps go through sudo and say what they do
# first. --no-root skips them; --no-profile skips the `nix profile` step for a
# host that gets direnv, devenv and ccmux some other way (the README's "your
# own configuration"). `doctor` changes nothing and reports every
# prerequisite, `claude doctor`, and, run in a harness repo, the repo's
# settings symlink, direnv approval and hooks; exit 1 when one the harness
# needs is missing. That is the host half of the runbook's verification
# section. --dry-run prints every step and the command it would run, runs
# none of them and never calls sudo; --verbose prints each command first.
#
# The harness ref (what `nix profile add` installs from): --harness, else
# HARNESS_REF, else the receipt's, else the profile's ccmux entry, else
# github:bilibo/claude-nix-harness. A `path:/nix/store/...` ref warns: a
# later upgrade cannot move it.
#
# --trusted-user adds you to Nix's trusted-users. Not needed: the devenv
# cache goes into the root-owned nix.conf as a substituter, which is what
# devenv checks for. A trusted user can pass any option to the daemon
# (unsigned paths, other caches, sandbox off), and agents run as you, so the
# default keeps that door shut.
#
# The user-scope ~/.claude/settings.json gets the keys a repo file cannot
# carry: sandbox.network.strictAllowlist = true (an unlisted host is refused
# inside the sandbox instead of prompting; user-or-managed scope). With
# --no-account-sync also syncClaudeAiSkills = false and
# syncClaudeAiPlugins = false, so sessions load no skills or plugins from the
# claude.ai account (the harness reviews none of them). Only `false` is
# honoured, from user scope or above; the default leaves them alone. The
# other keys of that file are kept as they are.
#
# The receipt, ~/.local/state/claude-nix-harness/receipt.json, lists what
# bootstrap put on the host: profile packages, files (whole files, marker
# blocks, merged keys), dnf packages and root steps, the VS Code extension,
# the harness ref and revision. Each bootstrap and upgrade adds to it.
#
# `reset` reverses what the receipt lists (without one, the built-in lists:
# the nix packages, /nix, /etc/nix, the SELinux rule, the build users, the nix
# profile and caches, the direnv allow database, every user file above, the
# VS Code pieces) so the next run is from zero, and removes the receipt last.
# It asks before it starts unless --yes; it never touches the code root, so
# delete a test repo by hand.
# shellcheck disable=SC1091,SC2015,SC2016,SC2088  # system files are not inputs; `x && ok || miss` reports, ok never fails; jq filters go through jq_edit; ~ in messages is text
set -euo pipefail

CMD="${HARNESS_CMD:-bootstrap}"   # bootstrap, upgrade, doctor or reset: pkgs/harness.nix sets it
NO_ROOT=0; NO_PROFILE=0; TRUSTED_USER=0; NO_ACCOUNT_SYNC=0; YES=0; DRY_RUN=0; VERBOSE=0
CODE_ROOT="${HARNESS_CODE_ROOT:-$HOME/code/git}"
# Run straight from a checkout (bash pkgs/harness/bootstrap.sh), the checkout is the ref.
HARNESS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
HARNESS_REF="${HARNESS_REF:-path:$HARNESS_DIR}"
HARNESS_REF_FROM="${HARNESS_REF_FROM:-checkout}"
usage() { sed -n '/^#   harness /,/^# shellcheck/{/^# shellcheck/q;s/^# \{0,1\}//;p;}' "$0"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --verbose) VERBOSE=1 ;;
    --no-root) NO_ROOT=1 ;;
    --no-profile) NO_PROFILE=1 ;;
    --trusted-user) TRUSTED_USER=1 ;;
    --no-account-sync) NO_ACCOUNT_SYNC=1 ;;
    --code-root) CODE_ROOT="${2:?--code-root needs a directory}"; shift ;;
    --harness) HARNESS_REF="${2:?--harness needs a flake reference}"; HARNESS_REF_FROM=--harness; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "harness $CMD: unknown argument $1 (see --help)" >&2; exit 64 ;;
  esac
  shift
done
CODE_ROOT="${CODE_ROOT%/}"

# The marker text predates the harness CLI; it stays so that blocks written by
# earlier versions are still found (scripts/install.sh writes the same one).
MARK_BEGIN="# --- claude-nix-harness (scripts/bootstrap-fedora.sh) ---"
MARK_END="# --- end claude-nix-harness ---"
DEVENV_CACHE="https://devenv.cachix.org"
DEVENV_KEY="devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
MIN_CLAUDE="2.1.295"   # onFailure: block in hook registrations
MIN_DIRENV="2.38"      # require_allowed in .envrc
MIN_TMUX="3.2"         # extended-keys
RECEIPT="$HOME/.local/state/claude-nix-harness/receipt.json"
# The built-in lists: what bootstrap installs, and what reset and upgrade fall
# back to on a host without a receipt.
PROFILE_PKGS=(direnv devenv ccmux harness)
ROOT_RPMS=(nix nix-daemon bubblewrap socat tmux jq git-core policycoreutils-python-utils)
NIX_RPMS=(nix nix-daemon nix-legacy nix-core nix-libs nix-system nix-filesystem)

# Nix-built tools (devenv's fetcher included) look for the CA bundle at the
# NixOS and Debian path, or where NIX_SSL_CERT_FILE points. Fedora 44 keeps
# it only here (the legacy /etc/pki/tls/certs/ca-bundle.crt and
# /etc/ssl/certs/ca-bundle.crt links are gone, which is also why Fedora's
# own profile.d/nix-daemon.sh fails to set the variable).
CA_BUNDLE=""
for f in /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt; do
  [ -r "$f" ] && { CA_BUNDLE="$f"; break; }
done

missing=0; nmiss=0; nwarn=0
ok()   { printf 'ok    %s\n' "$*"; }
miss() { printf 'MISSING %s\n' "$*"; missing=1; nmiss=$((nmiss+1)); }
warn() { printf 'warn  %s\n' "$*"; nwarn=$((nwarn+1)); }
step() { printf '\n==> %s\n' "$*"; }
die()  { echo "harness $CMD: $*" >&2; exit 1; }
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }  # ver_ge <have> <want>
in_list() { local x="$1"; shift; printf '%s\n' "$@" | grep -q -x -F -e "$x"; }  # in_list <word> <list...>
json_list() { jq -n '$ARGS.positional' --args "$@"; }

# Fedora's profile.d puts ~/.nix-profile/bin and the default profile on PATH
# for new shells; this shell may predate the dnf step.
nix_path() {
  unset __ETC_PROFILE_NIX_SOURCED
  [ -r /etc/profile.d/nix-daemon.sh ] && . /etc/profile.d/nix-daemon.sh
  [ -n "${NIX_SSL_CERT_FILE:-}" ] || [ -z "$CA_BUNDLE" ] || export NIX_SSL_CERT_FILE="$CA_BUNDLE"
  return 0
}

# ---------------------------------------------------------------- changes
# Every write to the host goes through these, so --dry-run prints what would
# happen and runs nothing, sudo included, and --verbose prints each command.
run() { # run [-q] <command...>; -q drops the command's stdout
  local quiet=0
  [ "$1" = -q ] && { quiet=1; shift; }
  if [ "$DRY_RUN" = 1 ]; then printf '    would run:'; printf ' %q' "$@"; echo; return 0; fi
  if [ "$VERBOSE" = 1 ]; then printf '    +'; printf ' %q' "$@"; echo; fi
  if [ "$quiet" = 1 ]; then "$@" >/dev/null; else "$@"; fi
}

put_file() { # put_file <path> <content> [append]
  if [ "$DRY_RUN" = 1 ]; then printf '    would %s %s\n' "${3:-write}" "$1"; return 0; fi
  mkdir -p "$(dirname "$1")"
  if [ "${3:-}" = append ]; then printf '%s\n' "$2" >>"$1"; else printf '%s\n' "$2" >"$1"; fi
}

write_if_differs() { # write_if_differs <path> <content>
  if [ ! -e "$1" ] || [ "$(cat "$1")" != "$2" ]; then
    step "write $1"; put_file "$1" "$2"
  fi
}

jq_edit() { # jq_edit <file> <jq args...>: rewrite a JSON file, the rest of it kept
  local f="$1" tmp; shift
  if [ "$DRY_RUN" = 1 ]; then echo "    would rewrite $f (jq)"; return 0; fi
  mkdir -p "$(dirname "$f")"; [ -s "$f" ] || echo '{}' >"$f"
  tmp=$(mktemp)
  jq "$@" "$f" >"$tmp" && mv "$tmp" "$f"
}

root_write() { # root_write <path> <content>: a root-owned 0644 file, through sudo
  local tmp
  if [ "$DRY_RUN" = 1 ]; then echo "    would run: sudo install -m 0644 -o root -g root <new content> $1"; return 0; fi
  tmp=$(mktemp); printf '%s\n' "$2" >"$tmp"
  run sudo install -m 0644 -o root -g root "$tmp" "$1"; rm -f "$tmp"
}

# without_block <file>: the file without the harness block.
without_block() {
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$1" 2>/dev/null || true
}

# ---------------------------------------------------------------- receipt
# What this run put on the host, or found there in the harness's shape;
# write_receipt adds it to the receipt. scripts/install.sh hands over its own
# root steps in HARNESS_ROOT_PACKAGES and HARNESS_ROOT_STEPS.
R_PROFILE=(); R_FILES=(); R_EXT=()
read -r -a R_ROOT_PKGS <<<"${HARNESS_ROOT_PACKAGES:-}"
read -r -a R_ROOT_STEPS <<<"${HARNESS_ROOT_STEPS:-}"

record_file() { # record_file <file|block|keys> <path> [<key path as a JSON array>...]
  R_FILES+=("$(jq -cn --arg k "$1" --arg p "$2" '{kind: $k, path: $p} + ($ARGS.positional | map(fromjson) | if . == [] then {} else {keys: .} end)' --args "${@:3}")")
}

write_receipt() {
  local old=null new
  [ -s "$RECEIPT" ] && old=$(jq -c . "$RECEIPT" 2>/dev/null || echo null)
  # A host bootstrapped before receipts existed: the harness block in nix.conf
  # says the root steps were the harness's, so the receipt takes over the
  # lists reset used then.
  if [ "$old" = null ] && [ ${#R_ROOT_PKGS[@]} -eq 0 ] && grep -q -F "$MARK_BEGIN" /etc/nix/nix.conf 2>/dev/null; then
    R_ROOT_PKGS=("${NIX_RPMS[@]}"); R_ROOT_STEPS+=(nix.conf selinux nix-daemon.socket)
  fi
  new=$(jq -n --argjson old "$old" \
    --arg ref "$HARNESS_REF" --arg rev "${HARNESS_REV:-unknown}" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg root "$CODE_ROOT" \
    --argjson profile "$(json_list "${R_PROFILE[@]}")" \
    --argjson files "$(printf '%s\n' "${R_FILES[@]}" | jq -s .)" \
    --argjson pkgs "$(json_list "${R_ROOT_PKGS[@]}")" \
    --argjson steps "$(json_list "${R_ROOT_STEPS[@]}")" \
    --argjson ext "$(json_list "${R_EXT[@]}")" '
    def union(a; b): (a // []) + b | unique;
    { version: 1,
      harness: {ref: $ref, rev: $rev},
      timestamp: $ts,
      firstWritten: ($old.firstWritten // $ts),
      codeRoot: $root,
      profile: union($old.profile; $profile),
      files: (($old.files // []) + $files | group_by(.path)
              | map(.[0] + {keys: (map(.keys // []) | add | unique)} | if .keys == [] then del(.keys) else . end)),
      root: {packages: union($old.root.packages; $pkgs), steps: union($old.root.steps; $steps)},
      vscodeExtensions: union($old.vscodeExtensions; $ext) }')
  step "write the receipt $RECEIPT"
  [ "$VERBOSE" = 1 ] && printf '%s\n' "$new"
  put_file "$RECEIPT" "$new"
}

# What reset used before there was a receipt.
legacy_receipt() {
  jq -n --arg h "$HOME" --argjson pkgs "$(json_list "${NIX_RPMS[@]}")" --argjson profile "$(json_list "${PROFILE_PKGS[@]}")" '
    { version: 1, profile: $profile,
      root: {packages: $pkgs, steps: ["nix.conf", "selinux", "nix-daemon.socket"]},
      files: [
        {kind: "file",  path: "\($h)/.config/direnv/direnv.toml"},
        {kind: "block", path: "\($h)/.config/tmux/tmux.conf"},
        {kind: "file",  path: "\($h)/.bashrc.d/claude-nix-harness.sh"},
        {kind: "file",  path: "\($h)/.config/environment.d/50-claude-nix-harness.conf"},
        {kind: "keys",  path: "\($h)/.claude/settings.json", keys: [["sandbox", "network", "strictAllowlist"], ["syncClaudeAiSkills"], ["syncClaudeAiPlugins"]]},
        {kind: "keys",  path: "\($h)/.config/Code/User/settings.json", keys: [["direnv.path.executable"], ["direnv.extraEnv", "NIX_SSL_CERT_FILE"]]}
      ],
      vscodeExtensions: ["mkhl.direnv"] }'
}

RECEIPT_JSON=""; HAVE_RECEIPT=0
load_receipt() {
  if jq -e '.version == 1' "$RECEIPT" >/dev/null 2>&1; then
    RECEIPT_JSON=$(cat "$RECEIPT"); HAVE_RECEIPT=1
  else
    RECEIPT_JSON=$(legacy_receipt)
    echo "no receipt at $RECEIPT: $CMD uses the built-in lists"
  fi
}
rq() { jq -r "$1" <<<"$RECEIPT_JSON"; }  # rq <filter>: from the receipt, one value per line

# ---------------------------------------------------------------- preflight
[ -r /etc/os-release ] && . /etc/os-release
host_ok() { [ "${ID:-}" = fedora ] && [ "${VERSION_ID:-0}" -ge 44 ] 2>/dev/null; }
if [ "$CMD" != doctor ]; then
  [ "${ID:-}" = fedora ] || die "this is for Fedora (found ${ID:-unknown}); the dnf step is the only distro-specific part"
  host_ok || die "Fedora 44 or newer needed: the first release that packages nix and nix-daemon"
  [ "$(id -u)" != 0 ] || die "run as your own user; sudo is used where root is needed"
fi

# ---------------------------------------------------------------- root steps
root_steps() {
  local need=() p
  for p in "${ROOT_RPMS[@]}"; do rpm -q "$p" >/dev/null 2>&1 || need+=("$p"); done
  if [ ${#need[@]} -gt 0 ]; then
    step "dnf install ${need[*]}"
    run sudo dnf install -y "${need[@]}"
    R_ROOT_PKGS+=("${need[@]}")
  fi

  # Fedora's nix.conf already enables nix-command and flakes. The harness block
  # adds the devenv cache; trusted-users only on request (header).
  local conf=/etc/nix/nix.conf want
  # Everything but a previous harness block, then the block.
  want=$(without_block "$conf")
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
    root_write "$conf" "$want"
    systemctl is-active -q nix-daemon.service && run sudo systemctl restart nix-daemon.service
  fi
  R_ROOT_STEPS+=(nix.conf)

  # SELinux: /nix gets default_t without a policy, and systemd (init_t) may
  # not create a socket in a default_t directory ("Failed to create listening
  # socket: Permission denied", no AVC in the journal when auditd runs). The
  # Determinate installer's nix.fc labels the socket directory var_run_t, the
  # type /run has; same here, as a persistent file-context rule.
  if [ "$(getenforce 2>/dev/null)" != Disabled ] && ! matchpathcon -n /nix/var/nix/daemon-socket/socket 2>/dev/null | grep -q var_run_t; then
    step "SELinux: label /nix/var/nix/daemon-socket as var_run_t so systemd can create the daemon socket"
    run sudo semanage fcontext -a -t var_run_t '/nix/var/nix/daemon-socket(/.*)?'
    run sudo restorecon -RF /nix/var/nix/daemon-socket
    R_ROOT_STEPS+=(selinux)
  fi

  if ! systemctl is-enabled -q nix-daemon.socket 2>/dev/null || ! systemctl is-active -q nix-daemon.socket; then
    step "enable the nix-daemon socket"
    run sudo systemctl enable --now nix-daemon.socket
    R_ROOT_STEPS+=(nix-daemon.socket)
  fi
}

# ---------------------------------------------------------------- user steps
profile_has() { # profile_has <name>
  nix profile list --json 2>/dev/null \
    | jq -e --arg n "$1" '.elements | if type == "object" then has($n) else map((.attrPath // "") | endswith("." + $n)) | any end' >/dev/null
}
profile_url() { # profile_url <name>: the flake the profile entry was added from
  nix profile list --json 2>/dev/null \
    | jq -r --arg n "$1" '.elements | if type == "object" then (.[$n].originalUrl // "") else (map(select((.attrPath // "") | endswith("." + $n))) | .[0].originalUrl // "") end'
}

profile_steps() {
  local sub=install name url
  nix_path
  if ! command -v nix >/dev/null; then
    [ "$DRY_RUN" = 1 ] || die "nix not on PATH after the dnf step"
    for name in "${PROFILE_PKGS[@]}"; do step "nix profile add $HARNESS_REF#$name"; run nix profile add "$HARNESS_REF#$name"; done
    return 0
  fi
  nix store info >/dev/null 2>&1 || nix store ping >/dev/null 2>&1 || die "the nix daemon does not answer (systemctl status nix-daemon.socket)"
  nix profile add --help >/dev/null 2>&1 && sub=add
  for name in "${PROFILE_PKGS[@]}"; do
    if profile_has "$name"; then
      if [ "$CMD" = upgrade ]; then
        url=$(profile_url "$name")
        if [ "$url" = "$HARNESS_REF" ]; then step "nix profile upgrade $name"; run nix profile upgrade "$name"
        else
          step "nix profile: $name from $HARNESS_REF (was ${url:-unknown})"
          run nix profile remove "$name"; run nix profile "$sub" "$HARNESS_REF#$name"
        fi
      fi
    else
      step "nix profile $sub $HARNESS_REF#$name"
      [ "$name" = direnv ] && echo "    (direnv builds from source while nixpkgs ships < $MIN_DIRENV; a few minutes once)"
      run nix profile "$sub" "$HARNESS_REF#$name"
    fi
    R_PROFILE+=("$name")
  done
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
    write_if_differs "$f" "$direnv_toml"; record_file file "$f"
  fi

  # tmux: the home module's programs.tmux.extraConfig, appended once.
  f="$HOME/.config/tmux/tmux.conf"
  if ! grep -q -F "$MARK_BEGIN" "$f" 2>/dev/null; then
    step "append the harness block to $f"
    put_file "$f" "$(cat <<TMUX
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
)" append
  fi
  record_file block "$f"

  # bash: the direnv hook and the code root (home.sessionVariables). Fedora's
  # ~/.bashrc sources ~/.bashrc.d/* after /etc/bashrc has run profile.d, so
  # the nix profile is already on PATH here. No HARNESS_EXPECT_MANAGED: this
  # host has no managed settings by design.
  local root_expr="$CODE_ROOT"
  [[ "$root_expr" == "$HOME/"* ]] && root_expr="\$HOME/${root_expr#"$HOME/"}"
  f="$HOME/.bashrc.d/claude-nix-harness.sh"
  write_if_differs "$f" "$MARK_BEGIN
export HARNESS_CODE_ROOT=\"$root_expr\"
# Fedora's own profile.d/nix-daemon.sh only knows the legacy bundle paths.
[ -n \"\${NIX_SSL_CERT_FILE:-}\" ] || export NIX_SSL_CERT_FILE=\"${CA_BUNDLE:-/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem}\"
if command -v direnv >/dev/null 2>&1; then eval \"\$(direnv hook bash)\"; fi"
  record_file file "$f"

  # GUI session PATH: VS Code launched from the menu (and the claude it spawns)
  # otherwise never sees the nix profile. systemd user environment generator;
  # takes effect at the next login.
  f="$HOME/.config/environment.d/50-claude-nix-harness.conf"
  write_if_differs "$f" "$MARK_BEGIN
PATH=\$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:\$HOME/.local/bin:\$PATH
NIX_SSL_CERT_FILE=${CA_BUNDLE:-/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem}"
  record_file file "$f"

  [ -d "$CODE_ROOT" ] || { step "mkdir $CODE_ROOT"; run mkdir -p "$CODE_ROOT"; }

  # Claude Code user settings: the keys a repo file cannot carry (header).
  # Merged with jq so the rest of the file (theme, model, ...) stays.
  local cs="$HOME/.claude/settings.json" want keys=('["sandbox","network","strictAllowlist"]')
  want='{sandbox: {network: {strictAllowlist: true}}}'
  if [ "$NO_ACCOUNT_SYNC" = 1 ]; then
    want="$want + {syncClaudeAiSkills: false, syncClaudeAiPlugins: false}"
    keys+=('["syncClaudeAiSkills"]' '["syncClaudeAiPlugins"]')
  fi
  if ! jq -e --argjson w "$(jq -n "$want")" '. as $s | ($s * $w) == $s' "$cs" >/dev/null 2>&1; then
    step "set the user-scope sandbox keys in $cs"
    jq_edit "$cs" --argjson w "$(jq -n "$want")" '. * $w'
  fi
  record_file keys "$cs" "${keys[@]}"

  # VS Code: mkhl.direnv loads the devenv shell into the window (runbook,
  # daily flow); direnv.path makes it work before the next login too.
  if command -v code >/dev/null 2>&1; then
    if ! code --list-extensions 2>/dev/null | grep -q -i -x 'mkhl.direnv'; then
      step "code --install-extension mkhl.direnv"
      run -q code --install-extension mkhl.direnv
    fi
    R_EXT+=(mkhl.direnv)
    local vs="$HOME/.config/Code/User/settings.json" direnv_bin
    nix_path; direnv_bin=$(command -v direnv 2>/dev/null || echo "$HOME/.nix-profile/bin/direnv")
    if ! jq -e --arg p "$direnv_bin" --arg c "$CA_BUNDLE" \
         '.["direnv.path.executable"] == $p and .["direnv.extraEnv"].NIX_SSL_CERT_FILE == $c' "$vs" >/dev/null 2>&1; then
      step "set direnv.path.executable and direnv.extraEnv.NIX_SSL_CERT_FILE in $vs"
      jq_edit "$vs" --arg p "$direnv_bin" --arg c "$CA_BUNDLE" \
        '. + {"direnv.path.executable": $p} | .["direnv.extraEnv"] = ((.["direnv.extraEnv"] // {}) + {NIX_SSL_CERT_FILE: $c})'
    fi
    record_file keys "$vs" '["direnv.path.executable"]' '["direnv.extraEnv","NIX_SSL_CERT_FILE"]'
  fi
}

# ---------------------------------------------------------------- reset
# strip_block <file>: the file without the harness block; removes the file
# when nothing else is left.
strip_block() {
  local f="$1" rest
  [ -e "$f" ] || return 0
  grep -q -F "$MARK_BEGIN" "$f" || return 0
  rest=$(without_block "$f")
  if [ -z "$(printf '%s' "$rest" | tr -d '[:space:]')" ]; then step "remove $f"; run rm -f "$f"
  else step "remove the harness block from $f"; put_file "$f" "$rest"; fi
}

# strip_keys <file> <key paths, JSON>: the harness's keys out of a JSON file,
# then the objects they leave empty.
strip_keys() {
  local f="$1" k="$2"
  [ -s "$f" ] && jq -e --argjson k "$k" '. as $doc | any($k[]; . as $p | $doc | try (getpath($p) != null) catch false)' "$f" >/dev/null 2>&1 || return 0
  step "remove the harness keys from $f"
  jq_edit "$f" --argjson k "$k" 'reduce $k[] as $p (.; try delpaths([$p]) catch .)
    | reduce ($k[] | . as $p | range(length - 1; 0; -1) | $p[:.]) as $q (.; if getpath($q) == {} then delpaths([$q]) else . end)'
}

reset_steps() {
  local pkgs=() steps=() profile=() exts=() nix_ours=0 i p f kind keys answer
  load_receipt
  mapfile -t pkgs < <(rq '.root.packages[]?')
  mapfile -t steps < <(rq '.root.steps[]?')
  mapfile -t profile < <(rq '.profile[]?')
  mapfile -t exts < <(rq '.vscodeExtensions[]?')
  in_list nix "${pkgs[@]}" && nix_ours=1

  echo "This removes, on this host ($([ "$HAVE_RECEIPT" = 1 ] && echo "from the receipt" || echo "the built-in lists")):"
  if [ "$NO_ROOT" = 1 ]; then echo "  root:  nothing (--no-root)"
  else
    [ ${#pkgs[@]} -eq 0 ] || echo "  root:  the packages ${pkgs[*]} (and the dependencies dnf pulled in with them)"
    if [ "$nix_ours" = 1 ]; then echo "  root:  nix-daemon.socket, /nix and /etc/nix, the nixbld build users"
    elif in_list nix.conf "${steps[@]}"; then echo "  root:  the harness block in /etc/nix/nix.conf"; fi
    in_list selinux "${steps[@]}" && echo "  root:  the SELinux rule for the daemon socket"
  fi
  if [ "$nix_ours" = 1 ]; then
    echo "  user:  the nix profile and state (~/.nix-profile, ~/.local/state/nix), ~/.cache/nix,"
    echo "         ~/.cache/devenv, the direnv allow database (~/.local/share/direnv)"
  elif [ ${#profile[@]} -gt 0 ]; then echo "  user:  the profile packages ${profile[*]}"; fi
  rq '.files[] | "  \(.kind | . + " " * (6 - length)) \(.path)\(if .keys then " (" + (.keys | map(join(".")) | join(", ")) + ")" else "" end)"'
  [ ${#exts[@]} -eq 0 ] || echo "  VS Code extension ${exts[*]} and its settings"
  [ "$HAVE_RECEIPT" = 0 ] || echo "  the receipt, last"
  echo "Not touched: $CODE_ROOT (delete a test repo by hand), the rest of Claude Code's own files."
  if [ "$YES" != 1 ] && [ "$DRY_RUN" != 1 ]; then
    printf "Type 'reset' to continue: "; read -r answer; [ "$answer" = reset ] || die "aborted"
  fi

  if [ "$NO_ROOT" != 1 ]; then
    [ "$DRY_RUN" = 1 ] || sudo -v || die "sudo is needed for the root part (or pass --no-root)"
    if [ "$nix_ours" = 1 ] || in_list nix-daemon.socket "${steps[@]}"; then
      step "disable the nix daemon"
      run sudo systemctl disable --now nix-daemon.socket nix-daemon.service 2>/dev/null || true
    fi
    local installed=()
    for p in "${pkgs[@]}"; do rpm -q "$p" >/dev/null 2>&1 && installed+=("$p"); done
    if [ ${#installed[@]} -gt 0 ]; then step "dnf remove ${installed[*]}"; run sudo dnf remove -y "${installed[@]}"; fi
    if [ "$nix_ours" = 1 ]; then
      step "remove /nix and /etc/nix"
      run sudo rm -rf /nix /etc/nix
    elif in_list nix.conf "${steps[@]}" && grep -q -F "$MARK_BEGIN" /etc/nix/nix.conf 2>/dev/null; then
      step "remove the harness block from /etc/nix/nix.conf"
      root_write /etc/nix/nix.conf "$(without_block /etc/nix/nix.conf)"
    fi
    if in_list selinux "${steps[@]}" && [ "$(getenforce 2>/dev/null)" != Disabled ]; then
      step "remove the SELinux rule for the daemon socket"
      run sudo semanage fcontext -d '/nix/var/nix/daemon-socket(/.*)?' 2>/dev/null || true
    fi
    if [ "$nix_ours" = 1 ]; then
      step "remove the nixbld build users"
      for i in $(seq 1 10); do run sudo userdel "nixbld-$i" 2>/dev/null || true; done
      run sudo groupdel nixbld 2>/dev/null || true
    fi
  fi

  if [ "$nix_ours" = 1 ]; then
    step "remove the nix profile, caches and the direnv allow database"
    run rm -rf "$HOME/.nix-profile" "$HOME/.nix-defexpr" "$HOME/.nix-channels" "$HOME/.local/state/nix" \
           "$HOME/.cache/nix" "$HOME/.cache/devenv" "$HOME/.local/share/devenv" "$HOME/.local/share/direnv"
  else
    nix_path
    for p in "${profile[@]}"; do
      if command -v nix >/dev/null 2>&1 && profile_has "$p"; then step "nix profile remove $p"; run nix profile remove "$p"; fi
    done
    if in_list direnv "${profile[@]}" && [ -d "$HOME/.local/share/direnv" ]; then
      step "remove the direnv allow database"; run rm -rf "$HOME/.local/share/direnv"
    fi
  fi
  while IFS=$'\t' read -r kind f keys; do
    case "$kind" in
      file)
        if grep -q -F "$MARK_BEGIN" "$f" 2>/dev/null; then step "remove $f"; run rm -f "$f"
        elif [ -e "$f" ]; then warn "$f no longer carries the harness marker: left alone"; fi ;;
      block) strip_block "$f" ;;
      keys) strip_keys "$f" "$keys" ;;
    esac
  done < <(rq '.files[] | [.kind, .path, ((.keys // []) | tojson)] | @tsv')
  if [ ${#exts[@]} -gt 0 ] && command -v code >/dev/null 2>&1; then
    for p in "${exts[@]}"; do
      if code --list-extensions 2>/dev/null | grep -q -i -x "$p"; then
        step "code --uninstall-extension $p"; run -q code --uninstall-extension "$p" 2>/dev/null || true
      fi
    done
  fi
  if [ -e "$RECEIPT" ]; then
    step "remove the receipt $RECEIPT"
    run rm -f "$RECEIPT"; run rmdir --ignore-fail-on-non-empty "$(dirname "$RECEIPT")"
  fi
  cat <<NEXT

Reset done$([ "$DRY_RUN" = 1 ] && echo " (dry run: nothing changed)"). From zero again: open a new terminal (this one still has the old
PATH), delete a test repo if you want \`harness init\` from scratch, e.g.
  rm -rf $CODE_ROOT/raul/harness-test
then scripts/install.sh (from a checkout, or the curl line in the README) and
the rest of the runbook's "From zero" list. Log out and in once at the end for
GUI-launched VS Code.
NEXT
}

# ---------------------------------------------------------------- report
report() {
  nix_path
  local v
  if host_ok; then echo "host: Fedora ${VERSION_ID} ($(uname -m)), SELinux $(getenforce 2>/dev/null || echo unknown)"
  else miss "Fedora 44 or newer (found ${PRETTY_NAME:-no /etc/os-release}): bootstrap refuses to run here"; fi
  echo "harness: ${HARNESS_REV:-unknown}, ref $HARNESS_REF ($HARNESS_REF_FROM)"
  if [ -s "$RECEIPT" ]; then ok "receipt $RECEIPT (harness $(jq -r '.harness.rev // "?"' "$RECEIPT" 2>/dev/null), $(jq -r '.timestamp // "?"' "$RECEIPT" 2>/dev/null))"
  else warn "no receipt at $RECEIPT: reset and upgrade use the built-in lists (harness bootstrap writes one)"; fi

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
    miss "nix (scripts/install.sh, or dnf install nix nix-daemon)"
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
  local cs="$HOME/.claude/settings.json"
  if jq -e '.sandbox.network.strictAllowlist == true' "$cs" >/dev/null 2>&1; then ok "strict network allowlist in $cs (unlisted hosts refused, not prompted)"
  else miss "sandbox.network.strictAllowlist is not true in $cs (user-or-managed scope; the repo file cannot set it)"; fi
  if jq -e '.syncClaudeAiSkills == false and .syncClaudeAiPlugins == false' "$cs" >/dev/null 2>&1; then ok "account-synced skills and plugins off in $cs"
  else warn "account-synced skills and plugins load (syncClaudeAiSkills, syncClaudeAiPlugins; --no-account-sync turns them off)"; fi
  [ -r /etc/claude-code/managed-settings.json ] && warn "/etc/claude-code/managed-settings.json exists: this host carries managed settings, the harness assumed none" || ok "no managed settings (unmanaged host: the repo file is the whole harness)"

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

# claude doctor: Claude Code's own install and settings check, one line here
# (--verbose prints all of it).
claude_doctor() {
  local out rc
  command -v claude >/dev/null 2>&1 || return 0   # the report already says so
  out=$(timeout 60 claude doctor </dev/null 2>&1); rc=$?
  [ "$VERBOSE" = 1 ] && printf '%s\n' "$out" | sed 's/^/      /'
  if [ "$rc" = 0 ] && grep -q -i 'no installation issues' <<<"$out"; then ok "claude doctor: no installation issues"
  else warn "claude doctor: $(grep -i -m1 -E 'issue|warn|error|fail' <<<"$out" || echo "exit $rc") (run claude doctor)"; fi
}

# repo_report: the harness repo in the current directory, the same things
# `harness init` checks after the first shell entry.
repo_report() {
  local s=.claude/settings.json h n=0
  echo; echo "repo: $PWD"
  if [ -L "$s" ] && [ ! -e "$s" ]; then miss "$s is a dangling symlink to $(readlink "$s") (direnv reload rewrites it)"
  elif [ -L "$s" ] && [[ "$(readlink -f "$s")" == /nix/store/* ]]; then ok "$s -> $(readlink "$s")"
  elif [ -L "$s" ]; then miss "$s points outside /nix/store ($(readlink -f "$s")): not the devenv module's file"
  else miss "$s is a plain file, not the devenv module's store symlink (anything can edit it; direnv reload rewrites it)"; fi
  if ! command -v direnv >/dev/null 2>&1; then miss "direnv not on PATH: the repo shell cannot load"
  elif direnv status 2>/dev/null | grep -q -E '^Found RC allowed (0|true)$'; then ok "direnv: .envrc allowed"
  else miss "direnv: .envrc not allowed (read it, then direnv allow)"; fi
  [ -e "$s" ] || return 0
  # Every hook the file names exists, is executable and accepts an event it
  # does not handle (tests/project-settings-test.sh).
  while read -r h; do
    if [ -x "$h" ] && printf '{"hook_event_name":"Stop"}' | "$h" >/dev/null 2>&1; then n=$((n+1))
    else miss "hook not runnable: $h"; fi
  done < <(jq -r '[.hooks[][].hooks[].command] | unique[]' "$s" 2>/dev/null)
  [ "$n" -gt 0 ] && ok "$n hooks in $s runnable" || miss "no runnable hook in $s"
}

summary() { echo; echo "harness $CMD: $nmiss missing, $nwarn warnings"; }

case "$CMD" in
  reset)
    reset_steps; exit 0 ;;
  doctor)
    # A report goes on past a probe that fails.
    set +e
    report
    claude_doctor
    { [ -e .claude/settings.json ] || [ -L .claude/settings.json ]; } && [ -f .envrc ] && repo_report
    summary ;;
  bootstrap|upgrade)
    if [[ "$HARNESS_REF" == path:/nix/store/* ]]; then
      warn "the harness ref is this harness's store path ($HARNESS_REF_FROM): a later upgrade cannot move it; pass --harness github:bilibo/claude-nix-harness or --harness path:<checkout>"
    fi
    if [ "$CMD" = upgrade ]; then
      load_receipt
      [ "$HAVE_RECEIPT" = 0 ] || [ -z "$(rq '.profile[]?')" ] || mapfile -t PROFILE_PKGS < <(rq '.profile[]')
    fi
    [ "$NO_ROOT" = 1 ] || { [ "$DRY_RUN" = 1 ] || sudo -v || die "sudo is needed for dnf, /etc/nix/nix.conf and the nix-daemon socket (or pass --no-root after doing those by hand)"; root_steps; }
    [ "$NO_PROFILE" = 1 ] || profile_steps
    user_steps
    write_receipt
    echo
    report
    summary
    cat <<NEXT

Next: open a new terminal (PATH and NIX_SSL_CERT_FILE come from profile.d and ~/.bashrc.d), then
  harness init <customer>/<repo>                  # a harness repo under $CODE_ROOT
  harness check $CODE_ROOT/<customer>/<repo>       # the live checks (API calls)
Log out and in once so GUI-launched VS Code gets the nix profile on PATH.
NEXT
    ;;
  *) die "unknown command (bootstrap, upgrade, doctor or reset)" ;;
esac
[ "$missing" = 0 ]
