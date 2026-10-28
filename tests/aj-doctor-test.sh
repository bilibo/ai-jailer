#!/usr/bin/env bash
#   aj-doctor-test.sh <path-to-aj> <project-settings.json>
#
# `aj doctor` on a host that has nothing: an empty HOME, a PATH with no
# nix, claude, code, direnv or tmux (the Nix build sandbox is such a host).
# It must report MISSING lines, run to its summary and exit 1, never stop
# early; no claude is an info line and no tmux a warning, neither MISSING.
# Then the repo part, in three fake repos: the settings file as a
# store symlink, as a dangling symlink, as a plain file.
# The host line for a NixOS and a WSL os-release (fake markers; the build
# sandbox has no /etc/os-release, so the plain case has no host at all).
# The managed rules (absent: MISSING; present: ok, and every hook it names
# runs), the worker accounts (agents group, linger per member, the sudoers
# file checked with visudo -cf) and the caller's standing (worker, owner,
# neither), with getent, loginctl, sudo and visudo stubbed.
set -uo pipefail
aj="${1:?usage: aj-doctor-test.sh <aj> <project-settings.json>}"
settings="${2:?usage: aj-doctor-test.sh <aj> <project-settings.json>}"
pass=0; fail=0
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home"

# doctor <dir> [<path>]: aj doctor in <dir> with nothing (or only <path>)
# on PATH; sets out and rc.
doctor() {
  out=$(cd "$1" && env -i HOME="$tmp/home" PATH="${2:-/var/empty}" TMPDIR="$tmp" USER="${T_USER:-tester}" \
    AI_JAILER_OS_RELEASE="${OS_RELEASE:-/var/empty/none}" AI_JAILER_NIXOS_MARKER=/var/empty/none AI_JAILER_WSL_MARKER="${WSL_MARKER:-/var/empty/none}" \
    AI_JAILER_MANAGED_DIR="${MANAGED:-$tmp/no-managed}" AI_JAILER_SUDOERS="${SUDOERS:-$tmp/no-sudoers}" AI_JAILER_STORE_DIR="$tmp/store" \
    AI_JAILER_SYSTEM_BASHRC="${SYSTEM_BASHRC:-/var/empty/none}" ${DIRENV_CONFIG:+"DIRENV_CONFIG=$DIRENV_CONFIG"} \
    ${T_CODE_ROOT:+"AI_JAILER_CODE_ROOT=$T_CODE_ROOT"} ${T_PROJECT:+"AI_JAIL_PROJECT=$T_PROJECT"} \
    "$aj" doctor 2>&1); rc=$?
}
check() { # check <description> <want-regex>
  if [[ "$out" =~ $2 ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (/$2/)"; printf '%s\n' "$out" | sed 's/^/  /'; fi
}
refute() { # refute <description> <forbidden-regex>
  if [[ "$out" =~ $2 ]]; then fail=$((fail+1)); echo "FAIL: $1 (/$2/ matched)"; printf '%s\n' "$out" | sed 's/^/  /'; else pass=$((pass+1)); fi
}
exits() { # exits <description> <want>
  if [ "$rc" = "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (want exit $2, got $rc)"; fi
}

mkdir -p "$tmp/empty"
doctor "$tmp/empty"
exits "doctor exits 1 when something is missing" 1
check "nix reported missing"    'MISSING nix'
check "direnv reported missing" 'MISSING direnv'
check "ran to the summary"      'aj doctor: [0-9]+ missing, [0-9]+ warnings'
refute "no shell error"         'unbound variable|syntax error|line [0-9]+:|command not found'
refute "no repo part outside a repo" 'repo: '
# No managed settings: this host enforces nothing, and says so.
check "no managed settings is MISSING" 'MISSING no managed settings at [^ ]*/no-managed/managed-settings\.json: this host enforces nothing \(aj bootstrap --workers \.\.\. from the ai-jailer checkout.s devenv shell\)'
check "no getent: no agents group" 'info  no agents group: no worker users on this host'
refute "no sudoers verdict without the file" 'visudo'
refute "strictAllowlist is gone"  'strictAllowlist|strict network'
refute "account sync verdicts are gone" 'account-synced'
refute "role and managed-env lines are gone" 'AI_JAILER_ROLE|AI_JAILER_EXPECT_MANAGED'
refute "no store-wide managed warning" 'this host carries managed settings'
# No host claude is a supported shape (the plain WSL host: the VS Code
# extension's binary, the CLI from a repo's ai-jail.claudeCode.enable): an
# info line, no claude doctor. No host tmux is a warning: ajmux carries its
# own, attaching by hand needs one.
check "no claude is an info line" 'info  claude not on the host PATH: the VS Code extension brings its own; repos get the CLI from ai-jail\.claudeCode\.enable'
refute "no claude is not missing" 'MISSING claude'
refute "no claude doctor without claude" 'claude doctor:'
check "no tmux is a warning"    'warn  tmux not on the host PATH: ajmux brings its own'
refute "no tmux is not missing" 'MISSING tmux( [^a]|$)' # `tmux ai-jailer block` is the config file's line
# Counted: the same host with claude and tmux stubs has the same number
# missing and one warning fewer (tmux's; the info line counts nowhere).
summary_of() { [[ "$out" =~ aj\ doctor:\ ([0-9]+)\ missing,\ ([0-9]+)\ warnings ]] && echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"; }
read -r miss0 warn0 < <(summary_of)
mkdir -p "$tmp/cbin"
# shellcheck disable=SC2016  # the stub's own $1
printf '#!/bin/sh\ncase "$1" in --version) echo "2.1.305 (Claude Code)" ;; doctor) echo "No installation issues found" ;; esac\n' >"$tmp/cbin/claude"
printf '#!/bin/sh\necho "tmux 3.5a"\n' >"$tmp/cbin/tmux"; chmod +x "$tmp/cbin/claude" "$tmp/cbin/tmux"
doctor "$tmp/empty" "$tmp/cbin"
check "host claude reported"    'ok    claude 2\.1\.305 '
check "claude doctor with claude" 'ok    claude doctor: no installation issues'
check "host tmux reported"      'ok    tmux 3\.5a'
read -r miss1 warn1 < <(summary_of)
if [ -n "${miss0:-}" ] && [ "$miss0" = "${miss1:-}" ] && [ "$warn0" = "$((warn1 + 1))" ]; then pass=$((pass+1))
else fail=$((fail+1)); echo "FAIL: without claude and tmux: ${miss0:-?} missing, ${warn0:-?} warnings; with both: ${miss1:-?} missing, ${warn1:-?} warnings (want the same missing, one warning more)"; fi
printf '#!/bin/sh\necho "2.1.200 (Claude Code)"\n' >"$tmp/cbin/claude"
doctor "$tmp/empty" "$tmp/cbin"
check "an old host claude is still missing" 'MISSING claude 2\.1\.200 is older than'

mkdir -p "$tmp/repo/.claude"; touch "$tmp/repo/.envrc"
ln -s "$settings" "$tmp/repo/.claude/settings.json"
doctor "$tmp/repo"
exits "doctor in a repo, nothing on PATH" 1
check "repo part runs"          'repo: '
check "store symlink accepted"  'ok    \.claude/settings\.json -> /nix/store/'
check "direnv missing in repo"  'MISSING direnv not on PATH'
refute "the repo file carries no hooks to check" 'hooks in \.claude/settings\.json|hook not runnable'

rm "$tmp/repo/.claude/settings.json"; ln -s /nix/store/does-not-exist "$tmp/repo/.claude/settings.json"
doctor "$tmp/repo"
check "dangling symlink"        'MISSING \.claude/settings\.json is a dangling symlink'

rm "$tmp/repo/.claude/settings.json"; echo '{}' >"$tmp/repo/.claude/settings.json"
doctor "$tmp/repo"
check "plain file"              'MISSING \.claude/settings\.json is a plain file'

# Inside a session the sandbox masks the file as a character device: say so,
# never report the repo as broken. (-c follows the symlink.)
rm "$tmp/repo/.claude/settings.json"; ln -s /dev/null "$tmp/repo/.claude/settings.json"
doctor "$tmp/repo"
check "sandbox mask reported"   'warn  \.claude/settings\.json is masked by the sandbox'
refute "mask is no repo verdict" 'no runnable hook|plain file|dangling symlink|points outside'

# A `code` that answers nothing (the same sandbox): no extension verdict.
mkdir -p "$tmp/bin"; printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/code"; chmod +x "$tmp/bin/code"
doctor "$tmp/empty" "$tmp/bin"
check "silent code reported"    'warn  code is on PATH but answers nothing'
refute "no extension verdict"   'VS Code extension [a-z]+\.' # the verdict names the extension; the claude info line does not

# The host line: NixOS from os-release alone (the /etc/NIXOS marker is not
# visible from inside a session), WSL from its marker.
printf 'ID=nixos\nPRETTY_NAME="NixOS 26.11 (Xantusia)"\n' >"$tmp/os-release"
OS_RELEASE="$tmp/os-release" doctor "$tmp/empty"
check "nixos host line"         'host: NixOS 26.11 \(Xantusia\) .*nix from the system configuration, 0 home-manager owned files skipped'
check "nixos without a receipt is a warning too" 'warn  no receipt at'
# The user side from the system configuration (NixOS programs.direnv):
# direnv.toml under DIRENV_CONFIG and the hook in /etc/bashrc, nothing in HOME.
mkdir -p "$tmp/etc-direnv"; printf '[global]\nload_dotenv = false\nstrict_env = true\nwarn_timeout = "2m"\n' >"$tmp/etc-direnv/direnv.toml"
# shellcheck disable=SC2016  # the hook line as NixOS writes it
printf 'eval "$(/nix/store/x-direnv/bin/direnv hook bash)"\n' >"$tmp/etc-bashrc"
OS_RELEASE="$tmp/os-release" DIRENV_CONFIG="$tmp/etc-direnv" SYSTEM_BASHRC="$tmp/etc-bashrc" doctor "$tmp/empty"
check "direnv.toml from DIRENV_CONFIG" "ok    direnv\.toml $tmp/etc-direnv/direnv\.toml"
check "hook from the system bashrc" "ok    direnv hook in $tmp/etc-bashrc \(system configuration\)"
refute "no bashrc.d verdict with a system hook" 'bashrc\.d'
refute "no environment.d verdict on nixos" 'environment\.d'   # the profiles are on every session's PATH there
printf '[global]\nstrict_env = false\n' >"$tmp/etc-direnv/direnv.toml"
OS_RELEASE="$tmp/os-release" DIRENV_CONFIG="$tmp/etc-direnv" doctor "$tmp/empty"
check "a foreign direnv.toml is a warning" "warn  $tmp/etc-direnv/direnv\.toml exists and is not the ai-jailer one"
printf 'ID=ubuntu\nPRETTY_NAME="Ubuntu 26.10"\n' >"$tmp/os-release"; touch "$tmp/wsl"
OS_RELEASE="$tmp/os-release" WSL_MARKER="$tmp/wsl" doctor "$tmp/empty"
check "wsl host line"           'host: WSL2 \(Ubuntu 26.10\) '

# mkhl.direnv: a manual install in the WSL remote, so an info line there;
# MISSING elsewhere, where bootstrap installs it.
mkdir -p "$tmp/vbin"
# shellcheck disable=SC2016  # the stub's own $1
printf '#!/bin/sh\ncase "$1" in --version) echo 1.143.1 ;; --list-extensions) echo anthropic.claude-code ;; esac\n' >"$tmp/vbin/code"; chmod +x "$tmp/vbin/code"
WSL_MARKER="$tmp/wsl" doctor "$tmp/empty" "$tmp/vbin"
check "no mkhl.direnv on WSL is an info line" 'info  VS Code extension mkhl\.direnv not in the WSL remote'
refute "no mkhl.direnv on WSL is not missing" 'MISSING VS Code extension mkhl\.direnv'
doctor "$tmp/empty" "$tmp/vbin"
check "no mkhl.direnv elsewhere is missing" 'MISSING VS Code extension mkhl\.direnv'

# The environment lines: facts (info), counted nowhere.
doctor "$tmp/empty"
read -r miss1 warn1 < <(summary_of)
check "code root default"       "info  AI_JAILER_CODE_ROOT $tmp/home/code/git \\(default\\)"
check "project unset"           "info  AI_JAIL_PROJECT unset: not inside a jail's shell"
T_CODE_ROOT=/srv/code T_PROJECT=acme/app doctor "$tmp/empty"
read -r miss2 warn2 < <(summary_of)
check "code root set"           'info  AI_JAILER_CODE_ROOT /srv/code[[:space:]]'
check "project set"             'info  AI_JAIL_PROJECT acme/app[[:space:]]'
if [ "$miss1" = "$miss2" ] && [ "$warn1" = "$warn2" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: counts: missing $miss1/$miss2, warnings $warn1/$warn2 (want the same: the environment lines count nowhere)"; fi

# The managed rules present: ok, and every hook they name must run.
mkdir -p "$tmp/managed/hooks"
printf '#!/bin/sh\nexit 0\n' >"$tmp/managed/hooks/env-guard.sh"; chmod +x "$tmp/managed/hooks/env-guard.sh"
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"%s/managed/hooks/env-guard.sh"}]}]}}\n' "$tmp" >"$tmp/managed/managed-settings.json"
MANAGED="$tmp/managed" doctor "$tmp/empty"
check "managed settings present" "ok    managed settings $tmp/managed/managed-settings\\.json"
check "managed hooks run"       "ok    1 hooks in $tmp/managed/managed-settings\\.json runnable"
refute "managed present is not missing" 'MISSING no managed settings|hook not runnable'
chmod -x "$tmp/managed/hooks/env-guard.sh"
MANAGED="$tmp/managed" doctor "$tmp/empty"
check "a hook that cannot run"  "MISSING hook not runnable: $tmp/managed/hooks/env-guard\\.sh"
check "no runnable hook left"   'MISSING no runnable hook in '
chmod +x "$tmp/managed/hooks/env-guard.sh"

# The worker accounts, with getent, loginctl, sudo and visudo stubbed. Group
# lines are getent's: name:x:gid:members.
mkdir -p "$tmp/abin"
printf 'agents:x:100:w-acme,w-beta\nw-acme:x:101:raul\nw-beta:x:102:raul\nusers:x:103:stranger\n' >"$tmp/groups"
cat >"$tmp/abin/getent" <<EOF
#!/bin/sh
[ "\$1" = group ] || exit 2
[ -n "\$2" ] || { cat "$tmp/groups"; exit 0; }
grep "^\$2:" "$tmp/groups" || exit 2
EOF
cat >"$tmp/abin/loginctl" <<EOF
#!/bin/sh
[ "\$1" = show-user ] || exit 1
if grep -q -x "\$2" "$tmp/lingering"; then echo Linger=yes; else echo Linger=no; fi
EOF
# shellcheck disable=SC2016  # the stub's own $1
printf '#!/bin/sh\n[ "$1" = -n ] && shift\nexec "$@"\n' >"$tmp/abin/sudo"
cat >"$tmp/abin/visudo" <<EOF
#!/bin/sh
if [ -e "$tmp/visudo-bad" ]; then echo "parse error in \$2 near line 1"; exit 1; fi
EOF
chmod +x "$tmp/abin/getent" "$tmp/abin/loginctl" "$tmp/abin/sudo" "$tmp/abin/visudo"
echo w-acme >"$tmp/lingering"
doctor "$tmp/empty" "$tmp/abin"
check "agents members"          'info  agents group members: w-acme,w-beta'
check "linger on"               'ok    linger on for w-acme'
check "linger off is a warning" 'warn  linger is off for w-beta: .*loginctl enable-linger w-beta'
refute "linger off is not missing" 'MISSING linger'
refute "no sudoers verdict while the file is absent" 'visudo'
# Standing: in agents is a worker; in a w-* group an owner; else neither.
T_USER=w-acme doctor "$tmp/empty" "$tmp/abin"
check "standing: worker"        'info  standing: worker \(w-acme is in agents\)'
chmod 0755 "$tmp/home"
T_USER=raul doctor "$tmp/empty" "$tmp/abin"
check "standing: owner"         'info  standing: owner \(raul is a member of w-acme w-beta\)'
check "an open owner home is missing" "MISSING the home $tmp/home is world-accessible \(mode 755\): a worker can read it"
chmod 0750 "$tmp/home"
T_USER=raul doctor "$tmp/empty" "$tmp/abin"
check "a 0750 owner home is closed to the workers" "ok    the home $tmp/home is closed to the workers \(mode 750\)"
chmod 0700 "$tmp/home"
T_USER=stranger doctor "$tmp/empty" "$tmp/abin"
check "standing: neither"       'info  standing: neither worker nor owner \(stranger is in no agents group and no w-\* group\)'
# The sudoers file, checked with visudo -cf through sudo.
echo 'raul ALL=(%agents) NOPASSWD: ALL' >"$tmp/sudoers"
SUDOERS="$tmp/sudoers" doctor "$tmp/empty" "$tmp/abin"
check "sudoers passes visudo"   "ok    $tmp/sudoers passes visudo -cf"
touch "$tmp/visudo-bad"
SUDOERS="$tmp/sudoers" doctor "$tmp/empty" "$tmp/abin"
check "sudoers that fails"      "MISSING $tmp/sudoers fails visudo -cf"
rm "$tmp/visudo-bad"

out=$("$aj" --version 2>&1); rc=$?
exits "--version" 0; check "--version prints the revision" '^aj .+'
out=$("$aj" --help 2>&1); rc=$?
exits "--help" 0; check "--help lists the commands" 'bootstrap.*upgrade.*doctor.*init.*check.*reset'
out=$("$aj" doctor --help 2>&1); rc=$?
exits "doctor --help" 0; check "doctor --help is the bootstrap header" 'aj reset'
out=$("$aj" frobnicate 2>&1); rc=$?
exits "unknown command" 64

echo "aj-doctor-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
