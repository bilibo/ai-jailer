#!/usr/bin/env bash
#   harness-bootstrap-test.sh <path-to-harness>
#
# `harness bootstrap`, `doctor` and `reset` on a generic (non-Fedora) host
# with every host command stubbed: sudo (runs `install` as a plain copy and
# logs the rest), nix, sysctl, systemctl and the tools doctor looks for; a
# fake HOME, and the system files under a scratch directory (HARNESS_NIX_CONF,
# HARNESS_SYSCTL_DROPIN, HARNESS_NIX_INSTALLER, HARNESS_OS_RELEASE,
# HARNESS_CA_BUNDLE). Asserts the root steps (nix.conf with and without a
# flakes line; the user-namespace sysctl offered, declined and accepted; dnf
# on Fedora only), the user files per rc-file layout (none, Fedora's
# ~/.bashrc.d, a plain ~/.bashrc, zsh only, an existing ~/.tmux.conf, a
# foreign direnv.toml), idempotent re-runs, the receipt, reset undoing all of
# it, upgrade building before it removes, and reset doing nothing without a
# receipt. Assumes no controlling terminal and no getenforce or code on
# PATH, which the Nix build sandbox guarantees.
set -uo pipefail
harness="${1:?usage: harness-bootstrap-test.sh <harness>}"
pass=0; fail=0
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
log="$tmp/calls"
mark='# --- claude-nix-harness (scripts/bootstrap-fedora.sh) ---'
mkdir -p "$tmp/bin" "$tmp/etc" "$tmp/nix"; touch "$tmp/ca.pem"
# The nix-installer's uninstaller, where scripts/install.sh leaves it.
printf '#!/bin/sh\n' >"$tmp/nix/nix-installer"; chmod +x "$tmp/nix/nix-installer"

stub() { printf '#!/bin/sh\necho "%s $*" >>"$CALLS"\n%s\n' "$1" "$2" >"$tmp/bin/$1"; chmod +x "$tmp/bin/$1"; }
# sudo: `install SRC DST` lands as a copy under $tmp; a sysctl flips the fake
# restriction the way the kernel would; the rest is logged only.
stub sudo 'case "$1" in
  install) shift; while [ $# -gt 2 ]; do shift; done; mkdir -p "$(dirname "$2")"; cp "$1" "$2" ;;
  sysctl) case "$3" in *=0) rm -f "$RESTRICTED" ;; *=1) touch "$RESTRICTED" ;; esac ;;
esac; exit 0'
# nix: a profile that remembers what was added ($PROFILE_STATE, one name per line).
stub nix 'case "$1" in
  --version) echo "nix (Nix) 2.30.0" ;;
  profile) case "$2" in
    list) printf "{\"elements\":{"; sep=""; for n in $(cat "$PROFILE_STATE" 2>/dev/null); do printf "%s\"%s\":{}" "$sep" "$n"; sep=","; done; echo "}}" ;;
    add) [ "$3" = --help ] || echo "${3##*#}" >>"$PROFILE_STATE" ;;
    remove) grep -v -x -e "$3" "$PROFILE_STATE" >"$PROFILE_STATE.new" 2>/dev/null; mv "$PROFILE_STATE.new" "$PROFILE_STATE" ;;
  esac ;;
esac; exit 0'
stub sysctl 'case "$1 $2" in "-n kernel.apparmor_restrict_unprivileged_userns") if [ -e "$RESTRICTED" ]; then echo 1; else echo 0; fi; exit 0 ;; "-n "*) exit 1 ;; esac; exit 0'
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
  out=$(cd "$tmp" && env -i HOME="$home" PATH="$tmp/bin:$PATH" TMPDIR="$tmp" CALLS="$log" RESTRICTED="$tmp/restricted" USER=tester \
    PROFILE_STATE="$tmp/profile" HARNESS_REF=github:bilibo/claude-nix-harness HARNESS_ROOT_STEPS="${ROOT_STEPS-nix-installer}" \
    HARNESS_OS_RELEASE="$tmp/os-release" HARNESS_NIX_CONF="$tmp/etc/nix.conf" HARNESS_SYSCTL_DROPIN="$tmp/etc/99-userns.conf" \
    HARNESS_NIX_INSTALLER="$tmp/nix/nix-installer" HARNESS_CA_BUNDLE="$tmp/ca.pem" \
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

# 1. A fresh host, user namespaces confined, --yes: every root and user step.
touch "$tmp/restricted"
h="$tmp/home1"; mkdir -p "$h"; receipt="$h/.local/state/claude-nix-harness/receipt.json"
harness "$h" bootstrap --yes
exits "fresh bootstrap" 0
says "nothing missing"             'harness bootstrap: 0 missing'
says "ran to the end"              'harness init <customer>/<repo>'
called "sysctl applied"            '^sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0$'
file_is "drop-in" "$tmp/etc/99-userns.conf" 'kernel.apparmor_restrict_unprivileged_userns = 0'
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
in_json "strict allowlist" "$h/.claude/settings.json" '.sandbox.network.strictAllowlist == true'
in_json "env scrub key" "$h/.claude/settings.json" '.env.CLAUDE_CODE_SUBPROCESS_ENV_SCRUB == "1"'
in_json "receipt steps" "$receipt" '.root.steps | index("sysctl") and index("nix.conf") and index("nix-installer")'
in_json "bashrc recorded as a block" "$receipt" '[.files[] | select(.path | endswith("/.bashrc")) | .kind] == ["block"]'
in_json "profile recorded" "$receipt" '(.profile | sort) == ["ccmux","devenv","direnv","harness"]'
uncalled "no dnf off fedora"       'dnf'
says "doctor sees the sysctl gone" 'ok    no sysctl confines'
says "doctor sees the rc wiring"   'ok    ~/.bashrc sources ~/.bashrc.d'
says "doctor names the tmux file"  'ok    tmux harness block in ~/.config/tmux/tmux.conf'

# 2. Again: nothing written twice, no second sysctl.
harness "$h" bootstrap --yes
exits "re-run" 0
uncalled "no second sysctl"        'sysctl -w'
uncalled "nix.conf not rewritten"  'install .*nix.conf'
refutes "rc file not rewritten"    "==> write $h/.bashrc"
count_is "one block in ~/.bashrc" "$h/.bashrc" "$mark" 1
count_is "one block in tmux.conf" "$h/.config/tmux/tmux.conf" "$mark" 1
count_is "one block in nix.conf" "$tmp/etc/nix.conf" "$mark" 1

# 3. Declined (no --yes, no terminal): reported, printed for later, not in
# the receipt, offered again next time; doctor keeps naming it.
touch "$tmp/restricted"; rm -f "$tmp/etc/99-userns.conf"
h2="$tmp/home2"; mkdir -p "$h2"
harness "$h2" bootstrap
exits "declined leaves a MISSING" 1
says "declined reported"           'warn  declined: every Claude command is refused'
says "printed for later"           'Declined, run later.*sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 && echo'
says "the report names it"         'MISSING AppArmor confines unprivileged user namespaces'
uncalled "not applied"             'sysctl -w'
absent "no drop-in" "$tmp/etc/99-userns.conf"
in_json "not in the receipt" "$h2/.local/state/claude-nix-harness/receipt.json" '.root.steps | index("sysctl") | not'
harness "$h2" bootstrap
says "offered again"               'user namespaces: kernel.apparmor_restrict_unprivileged_userns is 1'
harness "$h2" doctor
exits "doctor on the confined host" 1
says "doctor names the sysctl"     'MISSING AppArmor confines unprivileged user namespaces'
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
touch "$tmp/restricted"; h8="$tmp/home8"; mkdir -p "$h8"
harness "$h8" bootstrap --dry-run
says "dry run shows the sysctl"    'would run: sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0'
absent "dry run writes no rc file" "$h8/.bashrc"
absent "dry run writes no receipt" "$h8/.local/state/claude-nix-harness/receipt.json"
uncalled "dry run calls no sudo"   '^sudo'
rm -f "$tmp/restricted"

# 11. Fedora 44: dnf for what rpm lacks, recorded; the host line says so.
printf 'ID=fedora\nVERSION_ID=44\nPRETTY_NAME="Fedora Linux 44"\n' >"$tmp/os-release"
h9="$tmp/home9"; mkdir -p "$h9"
ROOT_STEPS=nix-daemon.socket harness "$h9" bootstrap --yes
called "dnf on fedora"             '^sudo dnf install -y nix nix-daemon bubblewrap socat tmux jq git-core policycoreutils-python-utils$'
in_json "packages in the receipt" "$h9/.local/state/claude-nix-harness/receipt.json" '.root.packages | index("nix")'
says "fedora host line"            "nix from Fedora's packages"
ubuntu

# 12. reset on the first host (installer route, sysctl applied): all undone.
echo 'kernel.apparmor_restrict_unprivileged_userns = 0' >"$tmp/etc/99-userns.conf"
harness "$h" reset --yes
exits "reset" 0
says "plan names the uninstaller"  "root:  Nix, by $tmp/nix/nix-installer uninstall"
says "plan names the sysctl"       "root:  $tmp/etc/99-userns.conf, and the kernel's user-namespace restriction back on"
called "uninstall"                 "^sudo $tmp/nix/nix-installer uninstall --no-confirm$"
called "restriction back"          '^sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=1$'
called "drop-in removed"           "^sudo rm -f $tmp/etc/99-userns.conf$"
uncalled "no rm -rf /nix without dnf" 'rm -rf /nix'
uncalled "no daemon stop: the uninstaller does it" 'systemctl disable'
absent "~/.bashrc (only the block) removed" "$h/.bashrc"
absent "bashrc.d file removed" "$h/.bashrc.d/claude-nix-harness.sh"
absent "direnv.toml removed" "$h/.config/direnv/direnv.toml"
absent "tmux.conf removed" "$h/.config/tmux/tmux.conf"
absent "environment.d removed" "$h/.config/environment.d/50-claude-nix-harness.conf"
in_json "user settings keys stripped" "$h/.claude/settings.json" '.sandbox == null and .env == null'
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
# emptied the stub's profile.
printf '%s\n' direnv devenv ccmux harness >"$tmp/profile"
harness "$h7" upgrade --yes
exits "upgrade" 0
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

echo "harness-bootstrap-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
