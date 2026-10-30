#!/usr/bin/env bash
#   ajmux-test.sh <path-to-ajmux>
#
# `ajmux -n` prints the resolution instead of touching tmux, so most of this
# runs anywhere; the live cases at the end start private tmux servers (the
# tmux ajmux runs) and never touch the user's. The claude ajmux puts in the
# window: from PATH (a stub first on it, for every case that is not about
# where claude comes from), else from the repo's devenv shell through a
# stub direnv, else an error naming ai-jail.claudeCode.enable.
#
# The worker handover runs without root: stubs for id (the caller is
# $STUB_USER, default tester), getent (the users in $STUB_USERS exist) and
# sudo (records its argv, then runs ajmux as the worker would see it: its
# own HOME, code root and tmux server).
set -uo pipefail
ajmux="${1:?usage: ajmux-test.sh <ajmux>}"
pass=0; fail=0
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
root="$tmp/code/git"
mkdir -p "$root/acme/infra/modules/net" "$root/acme/infra/.claude/worktrees/wt1" "$root/acme/app" "$tmp/elsewhere" "$tmp/hostbin" "$tmp/ubin"
export AI_JAILER_CODE_ROOT="$root"
unset AI_JAIL_PROJECT AI_JAIL_PROJECT_DIR AI_JAILER_WORKER_PREFIX STUB_USER STUB_USERS
nl=$'\n'
printf '#!/bin/sh\nexit 0\n' >"$tmp/hostbin/claude"; chmod +x "$tmp/hostbin/claude"
realid=$(type -P id) || { echo "ajmux-test: no id on PATH"; exit 1; }
cat >"$tmp/ubin/id" <<EOF
#!$BASH
[ "\${1:-}" = -un ] || exec "$realid" "\$@"
echo "\${STUB_USER:-tester}"
EOF
cat >"$tmp/ubin/getent" <<EOF
#!$BASH
[ "\${1:-}" = passwd ] || exit 2
for u in \${STUB_USERS:-}; do [ "\$u" != "\${2:-}" ] || { echo "\$u:x:1001:1001::$tmp/home/\$u:$BASH"; exit 0; }; done
exit 2
EOF
cat >"$tmp/ubin/sudo" <<EOF
#!$BASH
printf '%s\n' "\$*" >>"$tmp/sudo.args"
[ "\${1:-}" = -u ] && [ "\${3:-}" = -i ] && [ "\${4:-}" = ajmux ] || { echo "sudo stub: unexpected argv: \$*" >&2; exit 1; }
w=\$2; shift 4
export HOME="$tmp/home/\$w" STUB_USER="\$w" AI_JAILER_CODE_ROOT="$tmp/home/\$w/code/git" TMUX_TMPDIR="$tmp/home/\$w/tmux"
unset AI_JAIL_PROJECT AI_JAIL_PROJECT_DIR TMUX TMUX_PANE
exec "$ajmux" "\$@"
EOF
chmod +x "$tmp/ubin/id" "$tmp/ubin/getent" "$tmp/ubin/sudo"
export PATH="$tmp/ubin:$tmp/hostbin:$PATH"
cl="${nl}claude=$tmp/hostbin/claude \\(PATH\\)$" # the last line of -n, with claude from PATH

# check <want-exit> <want-output-regex> <cwd> <args...>
check() {
  local want="$1" re="$2" dir="$3"; shift 3
  local out got
  out=$(cd "$dir" && "$ajmux" -n "$@" 2>&1); got=$?
  if [ "$got" = "$want" ] && [[ "$out" =~ $re ]]; then pass=$((pass+1)); else
    fail=$((fail+1)); echo "FAIL (want $want /$re/, got $got): cd $dir && ajmux -n $*"; echo "  $out"; fi
}
ok() { check 0 "$@"; }

# Explicit <org>/<repo>, from anywhere.
ok "session=acme-infra repo=$root/acme/infra" "$tmp/elsewhere" acme/infra
ok "session=acme-infra repo=$root/acme/infra args=--worktree" "$tmp/elsewhere" acme/infra --worktree
ok "session=acme-app repo=$root/acme/app" "$root/acme/infra" acme/app
# No argument: the repo containing the current directory.
ok "session=acme-infra repo=$root/acme/infra" "$root/acme/infra"
ok "session=acme-infra repo=$root/acme/infra" "$root/acme/infra/modules/net"
ok "session=acme-infra repo=$root/acme/infra" "$root/acme/infra/.claude/worktrees/wt1"
# Only claude args: project from the current directory.
ok "session=acme-infra repo=$root/acme/infra args=-p hi" "$root/acme/infra" -p hi
ok "session=acme-infra repo=$root/acme/infra args=--worktree" "$root/acme/infra/modules" --worktree
# A path instead of a name.
ok "session=acme-infra repo=$root/acme/infra" "$tmp/elsewhere" "$root/acme/infra"
ok "session=acme-infra repo=$root/acme/infra" "$root/acme" infra
ok "session=acme-infra repo=$root/acme/infra" "$root/acme/infra" .
ok "session=acme-app repo=$root/acme/app" "$root/acme/infra" ../app
# A name with more than two segments is the repo containing it, like a path.
ok "session=acme-infra repo=$root/acme/infra" "$tmp/elsewhere" acme/infra/modules/net
# The code root may be a symlink.
ln -s "$root" "$tmp/link"
AI_JAILER_CODE_ROOT="$tmp/link" ok "session=acme-infra repo=$root/acme/infra" "$tmp/elsewhere" acme/infra
AI_JAILER_CODE_ROOT="$tmp/link" ok "session=acme-infra repo=$root/acme/infra" "$root/acme/infra/modules"
# AI_JAIL_PROJECT (exported by the devenv shell) wins over cwd.
AI_JAIL_PROJECT=acme/app ok "session=acme-app repo=$root/acme/app" "$root/acme/infra"
# A clone outside the root: the devenv shell exports the project and its dir.
mkdir -p "$tmp/elsewhere/jailer"
AI_JAIL_PROJECT=local/jailer AI_JAIL_PROJECT_DIR="$tmp/elsewhere/jailer" ok "session=local-jailer repo=$tmp/elsewhere/jailer" "$tmp/elsewhere/jailer"
AI_JAIL_PROJECT=local/jailer AI_JAIL_PROJECT_DIR="$tmp/elsewhere/jailer" ok "session=local-jailer repo=$tmp/elsewhere/jailer args=-p hi" "$tmp" -p hi
# An explicit project still wins over the exported one.
AI_JAIL_PROJECT=local/jailer AI_JAIL_PROJECT_DIR="$tmp/elsewhere/jailer" ok "session=acme-app repo=$root/acme/app" "$tmp" acme/app
# The whole -n output of a direct run: no window or role line.
ok "^session=acme-infra repo=$root/acme/infra${cl}" "$root/acme/infra"
# Failures: outside the root, missing repo, org only.
check 64 "usage" "$tmp/elsewhere"
# No AI_JAILER_CODE_ROOT at all (install.sh route): the default root under $HOME, and usage still prints.
out=$(cd "$tmp/elsewhere" && env -u AI_JAILER_CODE_ROOT HOME="$tmp" "$ajmux" -n 2>&1); got=$?
if [ "$got" = 64 ] && [[ "$out" =~ usage ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: without AI_JAILER_CODE_ROOT: got $got: $out"; fi
check 66 "no such repo: $root/acme/missing \(give" "$tmp/elsewhere" acme/missing
check 66 "no such repo" "$tmp/elsewhere" infra
check 66 "not under" "$tmp" elsewhere
check 66 "not under" "$root" acme

# The worker handover. The caller is not w-acme and w-acme exists: hand
# over by name, also for a repo the caller has no copy of, and for a path
# or cwd under the caller's own root.
handover="^session=acme-x project=acme/x user=w-acme \(sudo -u w-acme -i ajmux acme/x\)$"
STUB_USERS=w-acme ok "$handover" "$tmp/elsewhere" acme/x
STUB_USERS="w-beta w-acme" ok "$handover" "$tmp/elsewhere" acme/x/sub
STUB_USERS=w-acme ok "^session=acme-infra project=acme/infra user=w-acme \(sudo -u w-acme -i ajmux acme/infra --worktree -p hi\)$" "$root/acme/infra/modules" --worktree -p hi
STUB_USERS=w-acme ok "^session=acme-infra project=acme/infra user=w-acme \(sudo -u w-acme -i ajmux acme/infra\)$" "$tmp/elsewhere" "$root/acme/infra"
STUB_USERS=w-acme AI_JAIL_PROJECT=local/jailer AI_JAIL_PROJECT_DIR="$tmp/elsewhere/jailer" ok "^session=acme-app project=acme/app user=w-acme " "$tmp/elsewhere/jailer" acme/app
# The worker itself: a direct run, no user= in the output.
STUB_USER=w-acme STUB_USERS=w-acme ok "^session=acme-infra repo=$root/acme/infra${cl}" "$tmp/elsewhere" acme/infra
STUB_USER=w-acme STUB_USERS=w-acme check 66 "^ajmux: no such repo: $root/acme/x \(give" "$tmp/elsewhere" acme/x
# Another org's worker is refused, before anything else.
STUB_USER=w-beta STUB_USERS="w-acme w-beta" check 66 "^ajmux: a worker cannot open another org's session \(w-acme\)$" "$tmp/elsewhere" acme/x
STUB_USER=w-beta STUB_USERS="w-acme w-beta" check 66 "^ajmux: a worker cannot open another org's session \(w-acme\)$" "$tmp/elsewhere" acme/infra
# No such user on the host: a direct run for the caller.
STUB_USERS=w-other ok "^session=acme-infra repo=$root/acme/infra${cl}" "$tmp/elsewhere" acme/infra
STUB_USERS=w-other check 66 "^ajmux: no such repo: $root/acme/x \(give" "$tmp/elsewhere" acme/x
# AI_JAILER_WORKER_PREFIX names the users; w-acme is then just another user.
AI_JAILER_WORKER_PREFIX=agent- STUB_USERS="w-acme agent-acme" ok "^session=acme-x project=acme/x user=agent-acme \(sudo -u agent-acme -i ajmux acme/x\)$" "$tmp/elsewhere" acme/x
AI_JAILER_WORKER_PREFIX=agent- STUB_USERS=w-acme check 66 "^ajmux: no such repo" "$tmp/elsewhere" acme/x
AI_JAILER_WORKER_PREFIX=agent- STUB_USER=agent-beta STUB_USERS=agent-acme check 66 "another org's session \(agent-acme\)$" "$tmp/elsewhere" acme/x
AI_JAILER_WORKER_PREFIX=agent- STUB_USER=w-beta STUB_USERS=agent-acme ok "user=agent-acme " "$tmp/elsewhere" acme/x

# Where the window's claude comes from. PATH first, by absolute path (the
# window gets the tmux server's PATH, not this one), even for a repo whose
# shell has one too.
mkdir -p "$tmp/dbin" "$root/acme/cli/.shell/bin" "$root/acme/blocked"; : >"$root/acme/blocked/.blocked"
printf '#!/bin/sh\nexit 0\n' >"$root/acme/cli/.shell/bin/claude"; chmod +x "$root/acme/cli/.shell/bin/claude"
ok "session=acme-app repo=$root/acme/app${cl}" "$tmp/elsewhere" acme/app
ok "session=acme-cli .*${cl}" "$tmp/elsewhere" acme/cli
# No claude on PATH (the VS Code extension's host): the repo's devenv shell,
# through direnv exec. The stub direnv puts <repo>/.shell/bin first on PATH,
# as a devenv shell with ai-jail.claudeCode.enable does, and fails like an
# .envrc not yet allowed where <repo>/.blocked exists.
cat >"$tmp/dbin/direnv" <<'EOF'
#!/bin/sh
[ "$1" = exec ] || exit 0
d=$2; shift 2
[ ! -e "$d/.blocked" ] || { echo "direnv: error $d/.envrc is blocked" >&2; exit 1; }
echo "direnv: loading $d/.envrc" >&2
PATH="$d/.shell/bin:$PATH" exec "$@"
EOF
chmod +x "$tmp/dbin/direnv"
PATH="$tmp/ubin:$tmp/dbin" ok "^session=acme-cli repo=$root/acme/cli${nl}claude=$root/acme/cli/\.shell/bin/claude \(direnv exec $root/acme/cli\)$" "$tmp/elsewhere" acme/cli
PATH="$tmp/ubin:$tmp/dbin" AI_JAIL_PROJECT=acme/cli ok "^session=acme-cli repo=$root/acme/cli${nl}claude=$root/acme/cli/\.shell/bin/claude \(direnv exec $root/acme/cli\)$" "$root/acme/cli"
# Neither: an error that names the option, never `command not found`.
nocli="; ai-jail\.claudeCode\.enable = true in $root/acme/[a-z]+/devenv\.nix puts claude in its shell \(with allow_unfree: true in devenv\.yaml\), then direnv allow$"
PATH="$tmp/ubin:$tmp/dbin" check 69 "^ajmux: no claude on PATH or in $root/acme/app's devenv shell${nocli}" "$tmp/elsewhere" acme/app
PATH="$tmp/ubin:$tmp/dbin" check 69 "^ajmux: no claude on PATH, and $root/acme/blocked's devenv shell does not load \(.*direnv allow $root/acme/blocked\)${nocli}" "$tmp/elsewhere" acme/blocked
PATH="$tmp/ubin" check 69 "^ajmux: no claude on PATH, and no direnv on PATH to load $root/acme/cli's devenv shell${nocli}" "$tmp/elsewhere" acme/cli

# --- Live: real windows, on private tmux servers --------------------------
# A stub claude records its window's name, directory, user and arguments,
# then closes its window, both by its own pane: the window is opened with
# -d, and a bare display-message or kill-window acts on the session's
# current window. The tmux is the one ajmux runs; TMUX_TMPDIR and
# the unset TMUX keep it off the user's server (the sudo stub gives each
# worker its own TMUX_TMPDIR, as its own UID would), and stdin from
# /dev/null makes the final attach fail instead of taking a terminal. HOME
# keeps the user's tmux.conf and shell rc out.
unset TMUX TMUX_PANE
wroot="$tmp/home/w-acme/code/git"
export TMUX_TMPDIR="$tmp/tmux"; mkdir -p "$TMUX_TMPDIR" "$tmp/bin" "$wroot/acme/x" "$tmp/home/w-acme/tmux"
# shellcheck disable=SC2016  # writeShellApplication's literal `export PATH="<runtime inputs>:$PATH"`
tmux_path=$(sed -n 's/^export PATH="\(.*\):\$PATH"$/\1/p' "$ajmux")
live_env=(HOME="$tmp" XDG_CONFIG_HOME="$tmp/.config" PATH="$tmp/ubin:$tmp/bin:$tmux_path:$PATH")
trap 'env "${live_env[@]}" tmux kill-server 2>/dev/null; env "${live_env[@]}" TMUX_TMPDIR="$tmp/home/w-acme/tmux" tmux kill-server 2>/dev/null; rm -rf "$tmp"' EXIT
cat >"$tmp/bin/claude" <<EOF
#!$BASH
printf 'window=%s pwd=%s user=%s args=%s\n' "\$(tmux display-message -p -t "\$TMUX_PANE" '#{window_name}')" "\$(pwd -P)" "\${STUB_USER:-tester}" "\$*" >>"$tmp/ran"
tmux kill-window -t "\$TMUX_PANE"
EOF
chmod +x "$tmp/bin/claude"; : >"$tmp/ran" ; : >"$tmp/sudo.args"
# live <want-regex> <cwd> [VAR=value...] <ajmux> [args...]
live() {
  local want="$1" dir="$2" before line i; shift 2
  before=$(wc -l <"$tmp/ran")
  (cd "$dir" && env "${live_env[@]}" "$@" </dev/null >/dev/null 2>&1)
  for i in $(seq 100); do [ "$(wc -l <"$tmp/ran")" -gt "$before" ] && break; sleep 0.1; done
  line=$(sed -n "$((before + 1))p" "$tmp/ran")
  if [[ "$line" =~ $want ]]; then pass=$((pass+1)); else
    fail=$((fail+1)); echo "FAIL (want /$want/): cd $dir && ${*/#"$ajmux"/ajmux}"; echo "  ${line:-no window ran (after ${i}x0.1 s)}"; fi
}
# No server yet: a new server and session, the window named claude.
live "^window=claude pwd=$root/acme/infra user=tester args=$" "$root/acme/infra" "$ajmux"
live "^window=claude pwd=$root/acme/app user=tester args=--worktree$" "$tmp/elsewhere" "$ajmux" acme/app --worktree
# A session that already exists gets a new window.
env "${live_env[@]}" tmux new-session -d -s acme-infra -c "$tmp" 'sleep 60'
live "^window=claude pwd=$root/acme/infra user=tester args=-p hi$" "$tmp/elsewhere" "$ajmux" acme/infra -p hi
# A session another terminal shows (a control-mode client stands in for it)
# gets its window, and this terminal a grouped view of its own,
# <session>-<pid>, so the two never follow each other. The attach fails
# here (no terminal), so the view stays and is looked for, then killed; a
# real attach sets destroy-unattached on it.
sleep 30 | env "${live_env[@]}" tmux -C attach-session -t acme-infra >/dev/null 2>&1 &
ctl=$!; sleep 0.5
live "^window=claude pwd=$root/acme/infra user=tester args=-p view$" "$tmp/elsewhere" "$ajmux" acme/infra -p view
views=$(env "${live_env[@]}" tmux list-sessions -F '#{session_name} #{session_group}' 2>/dev/null | grep -E '^acme-infra-[0-9]+ acme-infra$' || true)
if [ "$(wc -l <<<"$views")" = 1 ] && [ -n "$views" ]; then pass=$((pass+1)); else
  fail=$((fail+1)); echo "FAIL: want one grouped view acme-infra-<pid> in group acme-infra, got: $(env "${live_env[@]}" tmux list-sessions -F '#{session_name} #{session_group}' | tr '\n' ';')"; fi
env "${live_env[@]}" tmux kill-session -t "=${views%% *}" 2>/dev/null; kill "$ctl" 2>/dev/null
# No client on the session: no view is made, the attach targets the session.
live "^window=claude pwd=$root/acme/infra user=tester args=-p plain$" "$tmp/elsewhere" "$ajmux" acme/infra -p plain
if env "${live_env[@]}" tmux list-sessions -F '#{session_name}' | grep -q -E '^acme-infra-[0-9]+$'; then
  fail=$((fail+1)); echo "FAIL: a view was made with no client on acme-infra"; else pass=$((pass+1)); fi
# No claude where ajmux runs: the window runs the repo shell's, through the
# stub direnv.
cat >"$root/acme/cli/.shell/bin/claude" <<EOF
#!$BASH
printf 'shell-claude window=%s\n' "\$(tmux display-message -p -t "\$TMUX_PANE" '#{window_name}')" >>"$tmp/ran"
tmux kill-window -t "\$TMUX_PANE"
EOF
live '^shell-claude window=claude$' "$tmp/elsewhere" PATH="$tmp/ubin:$tmp/dbin:$tmux_path" "$ajmux" acme/cli
# The handover end to end: sudo gets exactly the name and the claude args,
# and the window runs as w-acme in w-acme's own code root, which the
# caller's root does not hold.
live "^window=claude pwd=$wroot/acme/x user=w-acme args=--worktree -p hi$" "$tmp/elsewhere" STUB_USERS=w-acme "$ajmux" acme/x --worktree -p hi
argv=$(cat "$tmp/sudo.args")
if [ "$argv" = "-u w-acme -i ajmux acme/x --worktree -p hi" ]; then pass=$((pass+1)); else
  fail=$((fail+1)); echo "FAIL: sudo argv: want '-u w-acme -i ajmux acme/x --worktree -p hi', got '$argv'"; fi

echo "ajmux-test ($(basename "$ajmux")): $pass passed, $fail failed"
[ "$fail" = 0 ]
