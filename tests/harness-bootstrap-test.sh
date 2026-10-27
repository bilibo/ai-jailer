#!/usr/bin/env bash
#   harness-bootstrap-test.sh <path-to-harness>
#
# `harness bootstrap`, `doctor` and `reset` on a generic (non-Fedora) host
# with every host command stubbed: sudo (runs `install` as a plain copy and
# logs the rest), nix, sysctl, systemctl and the tools doctor looks for; a
# fake HOME, and the system files under a scratch directory (HARNESS_NIX_CONF,
# HARNESS_SYSCTL_DROPIN, HARNESS_NIX_INSTALLER, HARNESS_OS_RELEASE,
# HARNESS_CA_BUNDLE; HARNESS_NIX_PROFILE_D empty, so the stub nix wins on a
# nix-installer host). Asserts the root steps (nix.conf with and without a
# flakes line; the AppArmor bwrap profile offered, declined and accepted
# where AppArmor confines user namespaces, the sysctl where an older kernel
# does; never dnf, which is scripts/install.sh's), the managed link, the
# worker users (--workers: groups, useradd, home mode, owner membership,
# linger, the sudoers rule and its visudo check, each worker's own bootstrap
# as that user, with --owner-sudo none and password and a visudo failure), the
# user files per rc-file layout (none, Fedora's ~/.bashrc.d, a plain
# ~/.bashrc, zsh only, an existing ~/.tmux.conf, a foreign direnv.toml),
# idempotent re-runs, the receipt, reset undoing all of it (and printing, not
# running, userdel), a receipt from before 2026-10-27 whose user-scope keys
# reset still strips, --account-sync rejected, upgrade building before it
# removes and handing the user steps to the upgraded harness, reset doing
# nothing without a receipt, the store-symlink guard on nix.conf, a NixOS host
# (no root step, the configuration.nix and harness.* lines printed,
# home-manager's files left alone), the Fedora host line from doctor and a WSL
# host line. Assumes no controlling terminal; the stub directory is the whole
# PATH (the harness adds coreutils, jq, git and friends in front, so a stub
# named like one of those never runs: account checks use getent, not id).
set -uo pipefail
harness="${1:?usage: harness-bootstrap-test.sh <harness>}"
pass=0; fail=0
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
log="$tmp/calls"
mark='# --- claude-nix-harness (scripts/bootstrap-fedora.sh) ---'
mkdir -p "$tmp/bin" "$tmp/etc" "$tmp/nix" "$tmp/store/managed/hooks" "$tmp/homes"; touch "$tmp/ca.pem" "$tmp/groups" "$tmp/users"
# The fake managed tree `nix build .#managed` links: settings naming one hook,
# which accepts every event.
printf '#!/bin/sh\nexit 0\n' >"$tmp/store/managed/hooks/env-guard.sh"; chmod +x "$tmp/store/managed/hooks/env-guard.sh"
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"%s/etc-claude-code/hooks/env-guard.sh"}]}]}}\n' "$tmp" >"$tmp/store/managed/managed-settings.json"
# The nix-installer's uninstaller, where scripts/install.sh leaves it.
printf '#!/bin/sh\n' >"$tmp/nix/nix-installer"; chmod +x "$tmp/nix/nix-installer"

stub() { printf '#!/bin/sh\necho "%s $*" >>"$CALLS"\n%s\n' "$1" "$2" >"$tmp/bin/$1"; chmod +x "$tmp/bin/$1"; }
# sudo: `install SRC DST` lands as a copy under $tmp; a sysctl flips the fake
# restriction the way the kernel would (RESTRICTED: the AppArmor one,
# CLONE_RESTRICTED: unprivileged_userns_clone); the rest is logged only.
#
# The account commands change a fake host kept in $STUB_GROUPS (lines "group
# member", or "group -" for an empty group) and $STUB_USERS (one login per
# line), so a second run finds them. sudo runs them, `nix`, `cat` and, for
# paths under the scratch directory only, `rm` and `chmod`; `-u <user> -i
# nix run ...` runs the harness with that user's HOME, one directory per user.
stub sudo '[ "$1" != -n ] || shift
case "$1" in
  install) shift; while [ $# -gt 2 ]; do shift; done; mkdir -p "$(dirname "$2")"; cp "$1" "$2" ;;
  sysctl) case "$3" in
    kernel.apparmor_restrict_unprivileged_userns=0) rm -f "$RESTRICTED" ;; kernel.apparmor_restrict_unprivileged_userns=1) touch "$RESTRICTED" ;;
    kernel.unprivileged_userns_clone=1) rm -f "$CLONE_RESTRICTED" ;; kernel.unprivileged_userns_clone=0) touch "$CLONE_RESTRICTED" ;;
  esac ;;
  groupadd|useradd|usermod|loginctl) "$@" ;;
  visudo|test) "$@"; exit $? ;;
  cat) "$@"; exit $? ;;
  */nix|nix) "$@" ;;
  rm|chmod) case "$*" in *"$STUBROOT"*) "$@" ;; esac ;;
  -u) u="$2"; shift 3; mkdir -p "$STUBROOT/home-$u"
    env -u HARNESS_ROOT_STEPS -u HARNESS_ROOT_PACKAGES HOME="$STUBROOT/home-$u" USER="$u" "$@"; exit $? ;;
esac; exit 0'
stub groupadd 'echo "$1 -" >>"$STUB_GROUPS"'
stub useradd 'for a; do u="$a"; done; echo "$u" >>"$STUB_USERS"; echo "agents $u" >>"$STUB_GROUPS"; mkdir -p "$STUBROOT/homes/$u"; chmod 0755 "$STUBROOT/homes/$u"'
stub usermod 'echo "$2 $3" >>"$STUB_GROUPS"'
stub loginctl 'case "$1" in
  enable-linger) touch "$STUBROOT/linger-$2" ;; disable-linger) rm -f "$STUBROOT/linger-$2" ;;
  show-user) if [ -e "$STUBROOT/linger-$2" ]; then echo Linger=yes; else echo Linger=no; fi ;;
esac'
# getent reads the fake host and logs nothing (the report calls it often).
cat >"$tmp/bin/getent" <<'EOF'
#!/bin/sh
members() { awk -v n="$1" '$1 == n && $2 != "-" { printf "%s%s", s, $2; s = "," }' "$STUB_GROUPS"; }
case "$1" in
  group)
    if [ -z "$2" ]; then
      for n in $(awk '{print $1}' "$STUB_GROUPS" 2>/dev/null | sort -u); do echo "$n:x:100:$(members "$n")"; done
      exit 0
    fi
    grep -q "^$2 " "$STUB_GROUPS" 2>/dev/null || exit 2
    echo "$2:x:100:$(members "$2")" ;;
  passwd) grep -q -x -e "$2" "$STUB_USERS" 2>/dev/null || exit 2; echo "$2:x:1001:1001::/home/$2:/bin/bash" ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$tmp/bin/getent"
stub visudo 'if [ -n "${STUB_VISUDO_FAIL:-}" ]; then echo "parse error"; exit 1; fi'
# nix: a profile that remembers what was added ($PROFILE_STATE, one name per line).
# `build --out-link P` links P to a fake managed tree; `run <ref> -- <args>`
# runs the harness under test.
stub nix 'case "$1" in
  --version) echo "nix (Nix) 2.30.0" ;;
  build) shift; out=""; pf=0
    while [ $# -gt 0 ]; do case "$1" in --out-link) out="$2"; shift ;; --print-out-paths) pf=1 ;; esac; shift; done
    [ -z "$out" ] || { rm -f "$out"; ln -s "$STUBROOT/store/managed" "$out"; }
    [ "$pf" = 0 ] || echo "$STUBROOT/store/managed" ;;
  run) shift; while [ "$1" != -- ]; do shift; done; shift; "$HARNESS_BIN" "$@"; exit $? ;;
  profile) case "$2" in
    list) printf "{\"elements\":{"; sep=""; for n in $(cat "$PROFILE_STATE" 2>/dev/null); do printf "%s\"%s\":{}" "$sep" "$n"; sep=","; done; echo "}}" ;;
    add) [ "$3" = --help ] || echo "${3##*#}" >>"$PROFILE_STATE" ;;
    remove) grep -v -x -e "$3" "$PROFILE_STATE" >"$PROFILE_STATE.new" 2>/dev/null; mv "$PROFILE_STATE.new" "$PROFILE_STATE" ;;
  esac ;;
esac; exit 0'
stub sysctl 'case "$1 $2" in
  "-n kernel.apparmor_restrict_unprivileged_userns") if [ -e "$RESTRICTED" ]; then echo 1; else echo 0; fi; exit 0 ;;
  "-n kernel.unprivileged_userns_clone") if [ -e "$CLONE_RESTRICTED" ]; then echo 0; else echo 1; fi; exit 0 ;;
  "-n "*) exit 1 ;; esac; exit 0'
stub systemctl 'exit 0'
stub rpm 'exit 1'
stub direnv 'echo 2.38.2'
stub devenv 'echo "devenv 2.4.0"'
stub ccmux ''
stub bwrap ''
stub socat ''
stub tmux 'echo "tmux 3.5a"'
stub claude 'case "$1" in --version) echo "2.1.305 (Claude Code)" ;; doctor) echo "No installation issues found" ;; esac'

ubuntu() { printf 'ID=ubuntu\nVERSION_ID="24.04"\nPRETTY_NAME="Ubuntu 24.04"\n' >"$tmp/os-release"; }
ubuntu

# harness <home> <command> [args...]: with the stubs, no terminal; sets out
# and rc, empties the log. ROOT_STEPS is what scripts/install.sh hands over
# (the installer by default; set it empty for a host that had Nix already).
harness() {
  local home="$1" cmd="$2"; shift 2
  : >"$log"
  out=$(cd "$tmp" && env -i HOME="$home" PATH="$tmp/bin" TMPDIR="$tmp" CALLS="$log" RESTRICTED="$tmp/restricted" CLONE_RESTRICTED="$tmp/clone-restricted" USER=tester \
    PROFILE_STATE="$tmp/profile" HARNESS_REF=github:bilibo/claude-nix-harness HARNESS_ROOT_STEPS="${ROOT_STEPS-nix-installer}" \
    STUBROOT="$tmp" STUB_GROUPS="$tmp/groups" STUB_USERS="$tmp/users" HARNESS_BIN="$harness" ${STUB_VISUDO_FAIL:+STUB_VISUDO_FAIL=1} \
    HARNESS_MANAGED_DIR="$tmp/etc-claude-code" HARNESS_SUDOERS="$tmp/etc/sudoers-claude" HARNESS_STORE_DIR="$tmp/store" HARNESS_HOME_BASE="$tmp/homes" \
    HARNESS_OS_RELEASE="$tmp/os-release" HARNESS_NIX_CONF="$tmp/etc/nix.conf" HARNESS_SYSCTL_DROPIN="$tmp/etc/99-userns.conf" HARNESS_APPARMOR_PROFILE="$tmp/etc/apparmor-bwrap" \
    HARNESS_NIX_INSTALLER="$tmp/nix/nix-installer" HARNESS_CA_BUNDLE="$tmp/ca.pem" HARNESS_NIX_PROFILE_D= \
    HARNESS_NIXOS_MARKER=/var/empty/none HARNESS_WSL_MARKER="${WSL_MARKER:-/var/empty/none}" \
    "$harness" "$cmd" "$@" 2>&1 </dev/null); rc=$?
}
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); echo "FAIL: $1"; printf '%s\n' "$out" | sed 's/^/  /'; }
exits()    { if [ "$rc" = "$2" ]; then ok; else bad "$1 (want exit $2, got $rc)"; fi; }
says()     { if [[ "$out" =~ $2 ]]; then ok; else bad "$1 (/$2/)"; fi; }
refutes()  { if [[ "$out" =~ $2 ]]; then bad "$1 (/$2/ matched)"; else ok; fi; }
called()   { if grep -q -E -e "$2" "$log"; then ok; else bad "$1 (/$2/ not in the calls: $(tr '\n' ';' <"$log"))"; fi; }
uncalled() { if grep -q -E -e "$2" "$log"; then bad "$1 (/$2/ in the calls)"; else ok; fi; }
file_has() { if grep -q -E -e "$3" "$2" 2>/dev/null; then ok; else bad "$1 (/$3/ not in $2)"; fi; }
file_is()  { if [ "$(cat "$2" 2>/dev/null)" = "$3" ]; then ok; else bad "$1 ($2 is: $(cat "$2" 2>/dev/null))"; fi; }
absent()   { if [ -e "$2" ]; then bad "$1 ($2 exists)"; else ok; fi; }
count_is() { local n; n=$(grep -c -F -e "$3" "$2" 2>/dev/null); if [ "${n:-0}" = "$4" ]; then ok; else bad "$1 ($3 appears ${n:-0} times in $2, want $4)"; fi; }
in_json()  { if jq -e "$3" "$2" >/dev/null 2>&1; then ok; else bad "$1 ($3 false in $2)"; fi; }

# 1. A fresh host, user namespaces confined by AppArmor, --yes: every root
# and user step; the bwrap profile, not the sysctl.
touch "$tmp/restricted"; profile="$tmp/etc/apparmor-bwrap"
h="$tmp/home1"; mkdir -p "$h/.claude"; receipt="$h/.local/state/claude-nix-harness/receipt.json"
# The scrub key an earlier bootstrap wrote (2026-10-22), next to a key of the user's own.
echo '{"theme":"dark","env":{"CLAUDE_CODE_SUBPROCESS_ENV_SCRUB":"1"}}' >"$h/.claude/settings.json"
harness "$h" bootstrap --yes
exits "fresh bootstrap" 0
says "nothing missing"             'harness bootstrap: 0 missing'
says "ran to the end"              'harness init <customer>/<repo>'
uncalled "no sysctl for AppArmor"  'sysctl -w'
absent "no sysctl drop-in" "$tmp/etc/99-userns.conf"
file_has "profile header" "$profile" '^profile bwrap /usr/bin/bwrap flags=\(unconfined\) \{$'
file_has "profile userns" "$profile" '^  userns,$'
file_has "profile abi" "$profile" '^abi <abi/4.0>,$'
count_is "profile marker" "$profile" "$mark" 1
called "apparmor reloaded"         '^sudo systemctl reload apparmor$'
file_has "flakes in nix.conf" "$tmp/etc/nix.conf" '^experimental-features = nix-command flakes$'
file_has "devenv cache" "$tmp/etc/nix.conf" '^extra-substituters = https://devenv.cachix.org$'
count_is "nix.conf block" "$tmp/etc/nix.conf" "$mark" 1
for p in direnv devenv ccmux harness; do called "profile add $p" "^nix profile add github:bilibo/claude-nix-harness#$p$"; done
count_is "~/.bashrc created with the block" "$h/.bashrc" "$mark" 1
file_has "~/.bashrc sources the file" "$h/.bashrc" '^\[ -r ~/.bashrc.d/claude-nix-harness.sh \] && \. ~/.bashrc.d/claude-nix-harness.sh$'
file_has "bash hook" "$h/.bashrc.d/claude-nix-harness.sh" 'direnv hook bash'
file_has "code root" "$h/.bashrc.d/claude-nix-harness.sh" 'export HARNESS_CODE_ROOT="\$HOME/code/git"'
absent "no ~/.zshrc made up" "$h/.zshrc"
file_has "direnv.toml" "$h/.config/direnv/direnv.toml" '^strict_env = true$'
count_is "tmux block" "$h/.config/tmux/tmux.conf" "$mark" 1
absent "no ~/.tmux.conf made up" "$h/.tmux.conf"
file_has "environment.d" "$h/.config/environment.d/50-claude-nix-harness.conf" '^PATH='
in_json "scrub key removed, the user's key kept" "$h/.claude/settings.json" '.env == null and .theme == "dark"'
in_json "no harness keys written to the user settings" "$h/.claude/settings.json" '(has("sandbox") or has("syncClaudeAiSkills") or has("syncClaudeAiPlugins")) | not'
in_json "no user settings keys in the receipt" "$receipt" '[.files[] | select(.path | endswith("/.claude/settings.json"))] == []'
if [ "$(readlink "$tmp/etc-claude-code")" = "$tmp/store/managed" ]; then ok; else bad "the managed link points at the built tree"; fi
called "managed tree built and linked" "^sudo .*/nix build github:bilibo/claude-nix-harness#managed --out-link $tmp/etc-claude-code$"
in_json "managed in the receipt" "$receipt" '.root.steps | index("managed") and (index("sudoers") | not)'
in_json "no workers in the receipt" "$receipt" '.root.workers == []'
uncalled "no account without --workers" '^sudo (groupadd|useradd|usermod|loginctl|visudo)'
absent "no sudoers file without --workers" "$tmp/etc/sudoers-claude"
says "doctor sees the managed rules" "ok    managed settings $tmp/etc-claude-code/managed-settings.json"
says "doctor runs the managed hook" "ok    1 hooks in $tmp/etc-claude-code/managed-settings.json runnable"
says "doctor: no agents group"     'info  no agents group: no worker users on this host'
refutes "no strictAllowlist verdict" 'strictAllowlist|account-synced'
in_json "receipt steps" "$receipt" '.root.steps | index("apparmor") and index("nix.conf") and index("nix-installer") and (index("sysctl") | not)'
in_json "bashrc recorded as a block" "$receipt" '[.files[] | select(.path | endswith("/.bashrc")) | .kind] == ["block"]'
in_json "profile recorded" "$receipt" '(.profile | sort) == ["ccmux","devenv","direnv","harness"]'
uncalled "no dnf off fedora"       'dnf'
says "doctor sees the profile"     "ok    AppArmor confines unprivileged user namespaces; $profile lifts it for bwrap"
says "doctor sees the rc wiring"   'ok    ~/.bashrc sources ~/.bashrc.d'
says "doctor names the tmux file"  'ok    tmux harness block in ~/.config/tmux/tmux.conf'

# 2. Again: nothing written twice, no second profile.
harness "$h" bootstrap --yes
exits "re-run" 0
uncalled "no second profile"       'install .*apparmor-bwrap|systemctl reload apparmor'
uncalled "nix.conf not rewritten"  'install .*nix.conf'
uncalled "managed link not rebuilt" 'out-link'
refutes "rc file not rewritten"    "==> write $h/.bashrc"
count_is "one block in ~/.bashrc" "$h/.bashrc" "$mark" 1
count_is "one block in tmux.conf" "$h/.config/tmux/tmux.conf" "$mark" 1
count_is "one block in nix.conf" "$tmp/etc/nix.conf" "$mark" 1

# 3. Declined (no --yes, no terminal): reported, printed for later, not in
# the receipt, offered again next time; doctor keeps naming it.
touch "$tmp/restricted"; rm -f "$profile"
h2="$tmp/home2"; mkdir -p "$h2"
harness "$h2" bootstrap
exits "declined leaves a MISSING" 1
says "declined reported"           'warn  declined: every Claude command is refused'
says "printed for later"           "Declined, run later.*printf .*'abi <abi/4.0>,' .*'  userns,' .*\| sudo tee $profile && sudo systemctl reload apparmor"
says "the report names it"         "MISSING AppArmor confines unprivileged user namespaces \(kernel.apparmor_restrict_unprivileged_userns = 1\) and $profile is missing"
uncalled "not applied"             'sysctl -w|install .*apparmor-bwrap|reload apparmor'
absent "no profile" "$profile"
in_json "not in the receipt" "$h2/.local/state/claude-nix-harness/receipt.json" '.root.steps | (index("sysctl") or index("apparmor")) | not'
harness "$h2" bootstrap
says "offered again"               'user namespaces: AppArmor confines them \(kernel.apparmor_restrict_unprivileged_userns = 1\)'
harness "$h2" doctor
exits "doctor on the confined host" 1
says "doctor names the profile"    "MISSING AppArmor confines unprivileged user namespaces .*$profile is missing.*harness bootstrap writes the profile"
says "doctor host line"            'host: Ubuntu 24.04 .*nix from the nix-installer'
rm -f "$tmp/restricted"

# 4. Fedora's stock ~/.bashrc (sources ~/.bashrc.d): no block added to it.
h3="$tmp/home3"; mkdir -p "$h3"
printf '# .bashrc\nif [ -d ~/.bashrc.d ]; then for rc in ~/.bashrc.d/*; do . "$rc"; done; fi\n' >"$h3/.bashrc"
harness "$h3" bootstrap --yes
count_is "no block in a sourcing ~/.bashrc" "$h3/.bashrc" "$mark" 0
file_has "bashrc.d file still written" "$h3/.bashrc.d/claude-nix-harness.sh" 'direnv hook bash'
says "doctor accepts it"           'ok    ~/.bashrc sources ~/.bashrc.d'

# 5. zsh only: the block goes to ~/.zshrc, ~/.bashrc is not created.
h4="$tmp/home4"; mkdir -p "$h4"; echo '# zsh' >"$h4/.zshrc"
harness "$h4" bootstrap --yes
absent "no ~/.bashrc for a zsh user" "$h4/.bashrc"
file_has "zsh hook" "$h4/.zshrc" 'direnv hook zsh'
file_has "zsh code root" "$h4/.zshrc" 'export HARNESS_CODE_ROOT='
count_is "zsh block" "$h4/.zshrc" "$mark" 1
in_json "zshrc recorded as a block" "$h4/.local/state/claude-nix-harness/receipt.json" '[.files[] | select(.path | endswith("/.zshrc")) | .kind] == ["block"]'
says "doctor sees the zsh hook"    'ok    direnv hook in ~/.zshrc'

# 6. A plain ~/.bashrc and a ~/.zshrc: each gets its block, once, the rest
# kept. This host had Nix already (no installer step in its receipt).
h5="$tmp/home5"; mkdir -p "$h5"; echo 'export EDITOR=vi' >"$h5/.bashrc"; echo '# zsh' >"$h5/.zshrc"
ROOT_STEPS="" harness "$h5" bootstrap --yes; ROOT_STEPS="" harness "$h5" bootstrap --yes
count_is "one block in a plain ~/.bashrc" "$h5/.bashrc" "$mark" 1
file_has "the rest of ~/.bashrc kept" "$h5/.bashrc" '^export EDITOR=vi$'
count_is "one block in ~/.zshrc" "$h5/.zshrc" "$mark" 1

# 7. An existing ~/.tmux.conf: the block goes there, since tmux stops at it.
h6="$tmp/home6"; mkdir -p "$h6"; echo 'set -g mouse on' >"$h6/.tmux.conf"
harness "$h6" bootstrap --yes
count_is "block in ~/.tmux.conf" "$h6/.tmux.conf" "$mark" 1
file_has "the rest of ~/.tmux.conf kept" "$h6/.tmux.conf" '^set -g mouse on$'
absent "no second tmux file" "$h6/.config/tmux/tmux.conf"
says "doctor names ~/.tmux.conf"   'ok    tmux harness block in ~/.tmux.conf'

# 8. A foreign direnv.toml: warned about, left alone.
h7="$tmp/home7"; mkdir -p "$h7/.config/direnv"; echo '[global]' >"$h7/.config/direnv/direnv.toml"
harness "$h7" bootstrap --yes
says "foreign direnv.toml"         'warn  .*direnv.toml exists and is not the harness one'
file_is "left alone" "$h7/.config/direnv/direnv.toml" '[global]'

# 9. A nix.conf that already enables flakes: no second line, the rest kept.
printf 'build-users-group = nixbld\nexperimental-features = nix-command flakes\n' >"$tmp/etc/nix.conf"
harness "$h7" bootstrap --yes
count_is "one flakes line" "$tmp/etc/nix.conf" 'experimental-features' 1
file_has "the rest of nix.conf kept" "$tmp/etc/nix.conf" '^build-users-group = nixbld$'
file_has "the cache added" "$tmp/etc/nix.conf" '^extra-substituters'

# 10. --dry-run on a fresh home: the steps printed, nothing written, no sudo.
touch "$tmp/restricted"; rm -f "$profile"; h8="$tmp/home8"; mkdir -p "$h8"
harness "$h8" bootstrap --dry-run
says "dry run shows the profile"   "would run: sudo install -m 0644 -o root -g root <new content> $profile"
says "dry run shows the reload"    'would run: sudo systemctl reload apparmor'
absent "dry run writes no profile" "$profile"
absent "dry run writes no rc file" "$h8/.bashrc"
absent "dry run writes no receipt" "$h8/.local/state/claude-nix-harness/receipt.json"
uncalled "dry run calls no sudo"   '^sudo'
rm -f "$tmp/restricted"

# 11. Fedora 44: doctor's host line names the dnf route (scripts/install.sh
# runs dnf; the harness never does).
printf 'ID=fedora\nVERSION_ID=44\nPRETTY_NAME="Fedora Linux 44"\n' >"$tmp/os-release"
h9="$tmp/home9"; mkdir -p "$h9"
harness "$h9" doctor
says "fedora host line"            "nix from Fedora's packages"
uncalled "no dnf from doctor"      'dnf'
ubuntu

# 12. reset on the first host (installer route, profile written): all undone.
printf '%s\n' "$mark" 'profile bwrap /usr/bin/bwrap flags=(unconfined) {' '  userns,' '}' >"$profile"
harness "$h" reset --yes
exits "reset" 0
says "plan names the uninstaller"  "root:  Nix, by $tmp/nix/nix-installer uninstall"
says "plan names the profile"      "root:  $profile \(bwrap may no longer create user namespaces\), AppArmor reloaded"
called "uninstall"                 "^sudo $tmp/nix/nix-installer uninstall --no-confirm$"
called "profile removed"           "^sudo rm -f $profile$"
called "apparmor reloaded on reset" '^sudo systemctl reload apparmor$'
uncalled "no sysctl on reset"      'sysctl -w'
uncalled "no rm -rf /nix without dnf" 'rm -rf /nix'
uncalled "no daemon stop: the uninstaller does it" 'systemctl disable'
absent "~/.bashrc (only the block) removed" "$h/.bashrc"
absent "bashrc.d file removed" "$h/.bashrc.d/claude-nix-harness.sh"
absent "direnv.toml removed" "$h/.config/direnv/direnv.toml"
absent "tmux.conf removed" "$h/.config/tmux/tmux.conf"
absent "environment.d removed" "$h/.config/environment.d/50-claude-nix-harness.conf"
called "managed link removed"      "^sudo rm -f $tmp/etc-claude-code$"
absent "managed link gone" "$tmp/etc-claude-code"
in_json "the user's own settings kept" "$h/.claude/settings.json" '.theme == "dark"'
absent "receipt removed" "$receipt"
rm -f "$tmp/restricted"

# 13. reset on the plain-rc host: the blocks stripped, the rest kept.
harness "$h5" reset --yes
file_is "~/.bashrc without the block" "$h5/.bashrc" 'export EDITOR=vi'
count_is "~/.zshrc without the block" "$h5/.zshrc" "$mark" 0
file_has "the rest of ~/.zshrc kept" "$h5/.zshrc" '^# zsh$'
called "profile removed without Nix going" '^nix profile remove direnv$'

# 14. upgrade from another ref (the stub's entries carry no originalUrl): each
# package is built before its profile entry is removed. The resets above
# emptied the stub's profile. The profile then holds a harness that is not
# the running one (a stub under the fake home): the user steps go to it.
printf '%s\n' direnv devenv ccmux harness >"$tmp/profile"
mkdir -p "$h7/.nix-profile/bin"
printf '#!/bin/sh\necho "new-harness $*" >>"$CALLS"\n' >"$h7/.nix-profile/bin/harness"; chmod +x "$h7/.nix-profile/bin/harness"
harness "$h7" upgrade --yes
exits "upgrade" 0
called "user steps handed to the upgraded harness" '^new-harness bootstrap --no-root --no-profile --yes$'
refutes "old user steps not run"   'harness upgrade: [0-9]+ missing'
b=$(grep -n -m1 -x -F 'nix build --no-link github:bilibo/claude-nix-harness#direnv' "$log" | cut -d: -f1)
r=$(grep -n -m1 -x -F 'nix profile remove direnv' "$log" | cut -d: -f1)
if [ -n "$b" ] && [ -n "$r" ] && [ "$b" -lt "$r" ]; then ok; else bad "upgrade builds direnv before removing it (build at ${b:-none}, remove at ${r:-none}: $(tr '\n' ';' <"$log"))"; fi

# 15. reset on a host that never ran bootstrap: no receipt, nothing touched.
h10="$tmp/home10"; mkdir -p "$h10/.local/share/direnv/allow"; touch "$h10/.local/share/direnv/allow/x"
harness "$h10" reset --yes
exits "reset without a receipt" 0
says "nothing recorded"            'no receipt at .*: nothing recorded, nothing to reset'
uncalled "no sudo"                 '^sudo'
uncalled "no profile remove"       'nix profile remove'
file_is "direnv allow database kept" "$h10/.local/share/direnv/allow/x" ''

# 16. nix.conf is a symlink into the store (a NixOS system file) on a host
# that is not detected as NixOS: root_write refuses, nothing is installed.
store=$(readlink -f "$harness")   # any real store path; its content does not matter
rm -f "$tmp/etc/nix.conf"; ln -s "$store" "$tmp/etc/nix.conf"
h11="$tmp/home11"; mkdir -p "$h11"
harness "$h11" bootstrap --yes
exits "store symlink refused" 1
says "names the store and the option" "nix.conf is a symlink into the Nix store \($store\): the system configuration owns it; set nix.settings.substituters"
uncalled "nothing installed over it" 'install .*nix.conf'
if [ -L "$tmp/etc/nix.conf" ]; then ok; else bad "the symlink was replaced"; fi

# 17. NixOS, home-manager owns ~/.bashrc, direnv.toml and tmux.conf: no sudo
# at all, the configuration.nix lines printed, those three files untouched
# and named in the host line, the rest written as on any host.
printf 'ID=nixos\nVERSION_ID="26.11"\nPRETTY_NAME="NixOS 26.11 (Xantusia)"\n' >"$tmp/os-release"
touch "$tmp/restricted"; rm -f "$profile"; : >"$tmp/profile"
h12="$tmp/home12"; mkdir -p "$h12/.config/direnv" "$h12/.config/tmux"
ln -s "$store" "$h12/.bashrc"; ln -s "$store" "$h12/.config/direnv/direnv.toml"; ln -s "$store" "$h12/.config/tmux/tmux.conf"
harness "$h12" bootstrap --yes
uncalled "no sudo on nixos"        '^sudo'
says "nix.settings printed"        'NixOS: .*nix.conf is the system configuration.s and lacks flakes the devenv cache.*nix\.settings = \{.*experimental-features = \[ "nix-command" "flakes" \];'
says "sysctl as a NixOS option"    'boot\.kernel\.sysctl\."kernel\.apparmor_restrict_unprivileged_userns" = 0;'
says "bashrc skipped"              '~/\.bashrc is home-manager.s \(a store symlink\): left alone; it is set by programs\.direnv\.enableBashIntegration'
says "direnv.toml skipped"         '~/\.config/direnv/direnv\.toml is home-manager.s .*programs\.direnv\.config\.global'
says "tmux.conf skipped"           '~/\.config/tmux/tmux\.conf is home-manager.s .*programs\.tmux\.extraConfig'
for f in .bashrc .config/direnv/direnv.toml .config/tmux/tmux.conf; do
  if [ -L "$h12/$f" ] && [ "$(readlink "$h12/$f")" = "$store" ]; then ok; else bad "$f was changed"; fi
done
file_has "bashrc.d still written" "$h12/.bashrc.d/claude-nix-harness.sh" 'direnv hook bash'
uncalled "no account commands on nixos" 'groupadd|useradd|usermod|loginctl|visudo|nix build'
in_json "no root step in the receipt" "$h12/.local/state/claude-nix-harness/receipt.json" '.root.steps == ["nix-installer"]'
for p in direnv devenv ccmux harness; do called "profile add $p on nixos" "^nix profile add github:bilibo/claude-nix-harness#$p$"; done
says "host line"                   'host: NixOS 26.11 \(Xantusia\) .*nix from the system configuration, 3 home-manager owned files skipped'
says "doctor: hm bashrc ok"        'ok    ~/\.bashrc \(home-manager'
says "doctor: hm direnv.toml ok"   'ok    direnv\.toml \(home-manager\)'
says "doctor: hm tmux ok"          'ok    tmux config ~/\.config/tmux/tmux\.conf \(home-manager\)'
says "doctor: nixos fix for flakes" 'MISSING flakes not enabled in .*nix.settings in configuration.nix'
says "doctor: nixos fix for userns" 'MISSING AppArmor confines unprivileged user namespaces .*boot.kernel.sysctl in configuration.nix'
refutes "no bootstrap sysctl offer" 'apply with sudo now|would run: sudo'
harness "$h12" doctor
says "doctor host line"            'host: NixOS 26.11 .*3 home-manager owned files skipped'
rm -f "$tmp/restricted" "$tmp/etc/nix.conf"
ubuntu

# 18. WSL: the host line says so; nothing else changes here.
touch "$tmp/wsl"
WSL_MARKER="$tmp/wsl" harness "$h11" doctor
says "wsl host line"               'host: WSL2 \(Ubuntu 24.04\) '

# 19. An older Debian kernel (kernel.unprivileged_userns_clone = 0): the
# sysctl path as before, no profile; reset puts the restriction back.
rm -f "$tmp/restricted" "$profile"; touch "$tmp/clone-restricted"
h13="$tmp/home13"; mkdir -p "$h13"
harness "$h13" bootstrap --yes
says "clone sysctl offered"        'user namespaces: kernel.unprivileged_userns_clone is 0'
called "clone sysctl applied"      '^sudo sysctl -w kernel.unprivileged_userns_clone=1$'
file_is "clone drop-in" "$tmp/etc/99-userns.conf" 'kernel.unprivileged_userns_clone = 1'
absent "no profile for the clone sysctl" "$profile"
uncalled "no apparmor reload"      'reload apparmor'
in_json "sysctl in the receipt" "$h13/.local/state/claude-nix-harness/receipt.json" '.root.steps | index("sysctl") and (index("apparmor") | not)'
says "doctor sees the sysctl gone" 'ok    no sysctl confines'
harness "$h13" reset --yes
says "plan names the sysctl"       "root:  $tmp/etc/99-userns.conf, and the kernel's user-namespace restriction back on"
called "clone restriction back"    '^sudo sysctl -w kernel.unprivileged_userns_clone=0$'
called "clone drop-in removed"     "^sudo rm -f $tmp/etc/99-userns.conf$"
rm -f "$tmp/clone-restricted" "$tmp/etc/99-userns.conf"

# 20. --workers acme,beta on a host that had Nix already: the managed link,
# then per worker the group, user, home mode, owner membership and linger,
# then the sudo rule and its visudo check, then each worker's own bootstrap
# (the stub sudo runs it with that user's HOME). Order and argv are exact.
: >"$tmp/groups"; : >"$tmp/users"; rm -rf "$tmp/etc-claude-code" "$tmp/homes" "$tmp/etc/sudoers-claude"; rm -f "$tmp"/linger-*
rm -rf "$tmp"/home-w-*; mkdir -p "$tmp/homes"
h15="$tmp/home15"; mkdir -p "$h15"; receipt15="$h15/.local/state/claude-nix-harness/receipt.json"
account_calls() { grep -E "^sudo (/.*nix build|groupadd|useradd|chmod|usermod|loginctl|visudo|install .*sudoers|-u)" "$log" | sed -e "s#$tmp/tmp\\.[A-Za-z0-9]*#TMPFILE#" -e "s#$tmp#T#g"; }
ROOT_STEPS="" harness "$h15" bootstrap --yes --workers acme,beta
exits "workers bootstrap" 0
ref=github:bilibo/claude-nix-harness
want="sudo T/bin/nix build $ref#managed --out-link T/etc-claude-code
sudo groupadd agents
sudo groupadd w-acme
sudo useradd -m -g w-acme -G agents -s /bin/bash -c claude-nix-harness worker for acme w-acme
sudo chmod 0750 T/homes/w-acme
sudo usermod -aG w-acme tester
sudo loginctl enable-linger w-acme
sudo groupadd w-beta
sudo useradd -m -g w-beta -G agents -s /bin/bash -c claude-nix-harness worker for beta w-beta
sudo chmod 0750 T/homes/w-beta
sudo usermod -aG w-beta tester
sudo loginctl enable-linger w-beta
sudo install -m 0440 -o root -g root TMPFILE T/etc/sudoers-claude
sudo visudo -cf T/etc/sudoers-claude
sudo -u w-acme -i nix run $ref#harness -- bootstrap --no-root --yes --harness $ref
sudo -u w-beta -i nix run $ref#harness -- bootstrap --no-root --yes --harness $ref"
got=$(account_calls)
if [ "$got" = "$want" ]; then ok; else bad "the root commands, in order (got:
$got)"; fi
file_is "sudoers rule, exact" "$tmp/etc/sudoers-claude" 'tester ALL=(%agents) NOPASSWD: ALL'
in_json "receipt: workers" "$receipt15" '.root.workers == ["acme","beta"]'
in_json "receipt: managed and sudoers steps" "$receipt15" '.root.steps | index("managed") and index("sudoers")'
for w in acme beta; do
  wh="$tmp/home-w-$w"
  file_has "$w: direnv.toml written as that user" "$wh/.config/direnv/direnv.toml" '^strict_env = true$'
  file_has "$w: code root in bashrc.d" "$wh/.bashrc.d/claude-nix-harness.sh" 'export HARNESS_CODE_ROOT="\$HOME/code/git"'
  file_has "$w: git name" "$wh/.gitconfig" "^[[:space:]]*name = Claude \\($w\\)$"
  file_has "$w: git email" "$wh/.gitconfig" "^[[:space:]]*email = claude-$w@.+\\.invalid$"
  in_json "$w: git keys in its receipt" "$wh/.local/state/claude-nix-harness/receipt.json" '[.files[] | select(.path | endswith("/.gitconfig")) | .keys[]] == [["user","email"],["user","name"]] or [.files[] | select(.path | endswith("/.gitconfig")) | .keys[]] == [["user","name"],["user","email"]]'
  in_json "$w: no root steps of its own" "$wh/.local/state/claude-nix-harness/receipt.json" '.root.steps == [] and .root.workers == []'
done
absent "the owner's git identity is not touched" "$h15/.gitconfig"
says "doctor: agents members"      'info  agents group members: w-acme,w-beta'
says "doctor: linger on"           'ok    linger on for w-acme'
says "doctor: sudoers checked"     "ok    $tmp/etc/sudoers-claude passes visudo -cf"
says "doctor: standing owner"      'info  standing: owner \(tester is a member of w-acme w-beta\)'
says "doctor: managed hook"        "ok    1 hooks in $tmp/etc-claude-code/managed-settings.json runnable"

# A second run runs none of the root commands (the per-worker user step is
# not guarded: it is itself idempotent).
ROOT_STEPS="" harness "$h15" bootstrap --yes --workers acme,beta
exits "workers re-run" 0
got=$(account_calls | grep -v '^sudo -u ' || true)
if [ -z "$got" ]; then ok; else bad "the re-run ran root commands:
$got"; fi
count_is "still one group line per worker" "$tmp/groups" 'w-acme tester' 1
in_json "receipt: workers kept once" "$receipt15" '.root.workers == ["acme","beta"]'

# reset: the sudoers file, the link, linger; the users are only named.
harness "$h15" reset --yes
exits "reset with workers" 0
says "plan names the sudoers file" "root:  $tmp/etc/sudoers-claude"
says "plan names the link"         "root:  the $tmp/etc-claude-code link"
says "plan names linger"           'root:  linger off for w-acme'
called "sudoers removed"           "^sudo rm -f $tmp/etc/sudoers-claude$"
called "link removed"              "^sudo rm -f $tmp/etc-claude-code$"
called "linger off for acme"       '^sudo loginctl disable-linger w-acme$'
called "linger off for beta"       '^sudo loginctl disable-linger w-beta$'
absent "sudoers file gone" "$tmp/etc/sudoers-claude"
absent "managed link gone" "$tmp/etc-claude-code"
absent "linger gone" "$tmp/linger-w-acme"
says "userdel printed for acme"    'sudo userdel -r w-acme'
says "userdel printed for beta"    'sudo userdel -r w-beta'
uncalled "userdel not run"         'userdel'
file_has "the user is still there" "$tmp/users" '^w-acme$'
# A worker's own reset takes the git defaults out again, only because they
# are still the defaults.
sed -i 's/name = Claude (beta)/name = Real Name/' "$tmp/home-w-beta/.gitconfig"
harness "$tmp/home-w-acme" reset --yes --no-root
exits "worker reset" 0
if ! grep -q -E '(name|email) = ' "$tmp/home-w-acme/.gitconfig" 2>/dev/null; then ok; else bad "the default git identity was not removed ($(cat "$tmp/home-w-acme/.gitconfig"))"; fi
absent "worker direnv.toml removed" "$tmp/home-w-acme/.config/direnv/direnv.toml"
harness "$tmp/home-w-beta" reset --yes --no-root
if grep -q -E 'name = Real Name$' "$tmp/home-w-beta/.gitconfig" && ! grep -q -E 'email = ' "$tmp/home-w-beta/.gitconfig"; then ok; else bad "a git name set since was removed, or the default email stayed ($(cat "$tmp/home-w-beta/.gitconfig"))"; fi

# 21. --owner-sudo: none writes no rule; password drops NOPASSWD; a visudo
# failure removes the file and stops.
h16="$tmp/home16"; mkdir -p "$h16"
ROOT_STEPS="" harness "$h16" bootstrap --yes --workers gamma --owner-sudo none
exits "owner-sudo none" 0
absent "no sudoers file for none" "$tmp/etc/sudoers-claude"
uncalled "no visudo for none"      'visudo'
uncalled "no sudoers install for none" 'install .*sudoers'
called "the worker is still made"  '^sudo useradd -m -g w-gamma '
ROOT_STEPS="" harness "$h16" bootstrap --yes --workers delta --owner raul --owner-sudo password
file_is "password rule" "$tmp/etc/sudoers-claude" 'raul ALL=(%agents) ALL'
called "visudo for password"       "^sudo visudo -cf $tmp/etc/sudoers-claude$"
called "owner joins the group"     '^sudo usermod -aG w-delta raul$'
rm -f "$tmp/etc/sudoers-claude"
STUB_VISUDO_FAIL=1 ROOT_STEPS="" harness "$h16" bootstrap --yes --workers eps
exits "visudo failure" 1
says "visudo failure named"        "visudo rejected $tmp/etc/sudoers-claude; it was removed"
called "bad file removed"          "^sudo rm -f $tmp/etc/sudoers-claude$"
absent "bad sudoers file gone" "$tmp/etc/sudoers-claude"
ROOT_STEPS="" harness "$h16" bootstrap --yes --workers eps --owner-sudo maybe
exits "bad --owner-sudo" 64
ROOT_STEPS="" harness "$h16" bootstrap --yes --workers 'Bad Name'
exits "bad worker name" 64

# 22. --dry-run with a worker: every command printed, no sudo.
h17="$tmp/home17"; mkdir -p "$h17"
ROOT_STEPS="" harness "$h17" bootstrap --dry-run --workers zeta
says "dry run: user"               'would run: sudo useradd -m -g w-zeta -G agents -s /bin/bash -c claude-nix-harness\\ worker\\ for\\ zeta w-zeta'
says "dry run: worker bootstrap"   'would run: sudo -u w-zeta -i nix run github:bilibo/claude-nix-harness#harness -- bootstrap --no-root --yes --harness github:bilibo/claude-nix-harness'
says "dry run: sudoers"            "would run: sudo install -m 0440 -o root -g root <new content> $tmp/etc/sudoers-claude"
uncalled "dry run calls no sudo"   '^sudo'
absent "dry run: no w-zeta" "$tmp/homes/w-zeta"

# 23. /etc/claude-code that is a real directory is never replaced.
rm -f "$tmp/etc-claude-code"; mkdir -p "$tmp/etc-claude-code"
ROOT_STEPS="" harness "$h17" bootstrap --yes
exits "managed path is a directory" 1
says "refuses the directory"       "$tmp/etc-claude-code exists and is not a symlink"
rmdir "$tmp/etc-claude-code"

# 24. NixOS with workers: the module's options printed, nothing run.
printf 'ID=nixos\nVERSION_ID="26.11"\nPRETTY_NAME="NixOS 26.11 (Xantusia)"\n' >"$tmp/os-release"
h18="$tmp/home18"; mkdir -p "$h18"
harness "$h18" bootstrap --yes --workers acme,beta --owner raul
says "module enable"               'harness\.enable = true;'
says "module owner"                'harness\.owner = "raul";'
says "module worker acme"          'harness\.workers\.acme = \{ gitName = "Claude \(acme\)"; gitEmail = "claude-acme@[^"]*\.invalid"; \};'
says "module worker beta"          'harness\.workers\.beta = \{ gitName = "Claude \(beta\)"; '
uncalled "nothing run on nixos"    'useradd|groupadd|usermod|enable-linger|^sudo (install|/|-u)'
ubuntu

# 25. A receipt from before 2026-10-27 recorded the user-scope keys: reset
# still strips them, the user's own keys stay.
h19="$tmp/home19"; mkdir -p "$h19/.claude" "$h19/.local/state/claude-nix-harness"
echo '{"theme":"dark","sandbox":{"network":{"strictAllowlist":true}},"syncClaudeAiSkills":false,"syncClaudeAiPlugins":false}' >"$h19/.claude/settings.json"
jq -n --arg p "$h19/.claude/settings.json" '{version: 1, harness: {ref: "x", rev: "y"}, profile: [], vscodeExtensions: [], root: {packages: [], steps: []},
  files: [{kind: "keys", path: $p, keys: [["sandbox","network","strictAllowlist"],["syncClaudeAiSkills"],["syncClaudeAiPlugins"]]}]}' >"$h19/.local/state/claude-nix-harness/receipt.json"
harness "$h19" reset --yes --no-root
exits "old receipt reset" 0
in_json "old keys stripped, the user's kept" "$h19/.claude/settings.json" '.theme == "dark" and (has("sandbox") or has("syncClaudeAiSkills") or has("syncClaudeAiPlugins") | not)'
absent "old receipt removed" "$h19/.local/state/claude-nix-harness/receipt.json"

# 26. The removed flags are unknown arguments.
for f in --account-sync --no-account-sync; do
  harness "$h19" bootstrap --yes "$f"
  exits "$f rejected" 64
  says "$f is an unknown argument" "unknown argument $f"
done

echo "harness-bootstrap-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
