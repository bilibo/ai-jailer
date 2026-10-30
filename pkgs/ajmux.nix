# ajmux [-n] [<org>/<repo> | <path>] [claude args...]
# Starts or attaches the project's tmux session and runs claude in a window
# named `claude`. AI_JAIL_PROJECT is exported by the jail's devenv shell, so
# inside a repo (or its worktree) the project argument is optional; for a
# clone outside the code root the shell also exports AI_JAIL_PROJECT_DIR.
#
# Each org is a Linux user, ${AI_JAILER_WORKER_PREFIX:-w-}<org>, with
# its own tmux server. Run by anyone else, ajmux hands over with
# `sudo -u <worker> -i ajmux <org>/<repo> [claude args]` and does not
# touch tmux itself; run by that worker, it starts the session. A worker
# naming another org's project is refused (exit 66). With no such user
# on the host, ajmux runs directly for the caller.
#
# The handover always passes the name, never a path: a path under the
# caller's own home resolves against the caller's code root, and the worker
# resolves the name under its own AI_JAILER_CODE_ROOT, which comes from its
# login shell (hence `-i`). A name the caller's root does not hold is
# handed over unresolved; it is an error only on a direct run.
#
# claude is the one on PATH, else the target repo's devenv shell's
# (`direnv exec`), else an error naming ai-jail.claudeCode.enable.
# `-n` prints the resolution (or the handover) and exits, for
# tests/ajmux-test.sh. Exit codes: 64 usage, 66 no such repo or refused,
# 69 no claude.
{
  pkgs,
  codeRoot ? "$HOME/code/git",
}:
pkgs.writeShellApplication {
  name = "ajmux";
  # sudo, getent and id come from the host's PATH, which writeShellApplication
  # keeps after these: sudo has to be the host's setuid binary.
  runtimeInputs = [ pkgs.tmux ];
  text = ''
    usage() { echo "usage: ajmux [<org>/<repo> | <path>] [claude args]  (inside a repo under $root, the project is optional)" >&2; exit 64; }
    die() { echo "ajmux: $*" >&2; exit 66; }
    # Physical path, like the `pwd -P` in resolve, so a symlinked root still matches.
    root="''${AI_JAILER_CODE_ROOT:-${codeRoot}}"
    root=$(cd "$root" 2>/dev/null && pwd -P) || die "no such directory: $root"

    # resolve <dir>: the <org>/<repo> containing <dir>, or die.
    resolve() {
      local p rel a b
      p=$(cd "$1" 2>/dev/null && pwd -P) || die "no such directory: $1"
      [[ "$p" == "$root/"* ]] || die "$p is not under $root/<org>/<repo>"
      rel="''${p#"$root/"}"
      IFS=/ read -r a b _ <<<"$rel"
      [ -n "$a" ] && [ -n "$b" ] || die "$p is not under $root/<org>/<repo>"
      printf '%s/%s' "$a" "$b"
    }

    dry=0
    if [ "''${1:-}" = "-n" ] || [ "''${1:-}" = "--dry-run" ]; then dry=1; shift; fi

    missing=""
    if [ $# -ge 1 ] && [[ "$1" != -* ]]; then
      arg="$1"; shift
      if [[ "$arg" != /* && "$arg" != .* && -d "$root/$arg" ]]; then
        project=$(resolve "$root/$arg")
      elif [ -d "$arg" ]; then
        project=$(resolve "$arg")
      elif [[ "$arg" =~ ^([^/.][^/]*/[^/]+) ]]; then
        # Possibly a worker's repo the caller has no copy of.
        project="''${BASH_REMATCH[1]}" missing="$root/$arg"
      else
        die "no such repo: $root/$arg (give <org>/<repo>, or a path to a repo under $root)"
      fi
    elif [ -n "''${AI_JAIL_PROJECT:-}" ]; then
      project="$AI_JAIL_PROJECT"
    elif [[ "$PWD" == "$root/"* ]]; then
      project=$(resolve "$PWD")
    else
      usage
    fi
    session="''${project//\//-}"

    prefix="''${AI_JAILER_WORKER_PREFIX:-w-}"
    worker="$prefix''${project%%/*}"
    me=$(id -un)
    if [ "$me" != "$worker" ] && getent passwd "$worker" >/dev/null 2>&1; then
      case "$me" in "$prefix"*) die "a worker cannot open another org's session ($worker)" ;; esac
      if [ "$dry" = 1 ]; then
        printf 'session=%s project=%s user=%s (sudo -u %s -i ajmux %s' "$session" "$project" "$worker" "$worker" "$project"
        [ $# -eq 0 ] || printf ' %s' "$*"
        echo ")"; exit 0
      fi
      exec sudo -u "$worker" -i ajmux "$project" "$@"
    fi
    [ -z "$missing" ] || die "no such repo: $missing (give <org>/<repo>, or a path to a repo under $root)"

    if [ -n "''${AI_JAIL_PROJECT_DIR:-}" ] && [ "$project" = "''${AI_JAIL_PROJECT:-}" ]; then
      repo="$AI_JAIL_PROJECT_DIR"
    else
      repo="$root/$project"
    fi
    [ -d "$repo" ] || die "no such repo: $repo"

    # The window's claude. The launching PATH's first (a host-wide install,
    # or the repo shell ajmux runs in), by absolute path: the one `-n`
    # reports. Else the target repo's devenv shell
    # (ai-jail.claudeCode.enable): the window runs `direnv exec <repo>
    # claude`, so claude starts in that shell's environment. On a host whose
    # Claude Code is the VS Code extension's bundled binary, that is the only
    # CLI there is.
    nocli() { echo "ajmux: $1; ai-jail.claudeCode.enable = true in $repo/devenv.nix puts claude in its shell (with allow_unfree: true in devenv.yaml), then direnv allow" >&2; exit 69; }
    direnv=$(type -P direnv || true)
    if claude=$(type -P claude); then
      via=PATH
    elif [ -z "$direnv" ]; then
      nocli "no claude on PATH, and no direnv on PATH to load $repo's devenv shell"
    else
      rc=0
      claude=$("$direnv" exec "$repo" "$BASH" -c 'type -P claude || exit 3' 2>/dev/null) || rc=$?
      case "$rc" in
        0) via="direnv exec $repo" ;;
        3) nocli "no claude on PATH or in $repo's devenv shell" ;;
        *) nocli "no claude on PATH, and $repo's devenv shell does not load (read its .envrc and devenv files, then direnv allow $repo)" ;;
      esac
    fi

    if [ "$dry" = 1 ]; then
      printf 'session=%s repo=%s' "$session" "$repo"
      [ $# -eq 0 ] || printf ' args=%s' "$*"
      printf '\nclaude=%s (%s)' "$claude" "$via"
      echo; exit 0
    fi

    # `sudo -i` does not carry XDG_RUNTIME_DIR; linger keeps the worker's
    # /run/user/<uid>, and devenv and tmux look there. Assumed from the plan
    # (check V5), not yet verified live, 2026-10-27.
    uid=$(id -u)
    if [ -z "''${XDG_RUNTIME_DIR:-}" ] && [ -d "/run/user/$uid" ]; then
      export XDG_RUNTIME_DIR="/run/user/$uid"
    fi

    if [ "$via" = PATH ]; then
      printf -v command '%q ' "$claude" "$@"
    else
      printf -v command '%q ' "$direnv" exec "$repo" claude "$@"
    fi
    # Keep the window open after claude exits so the pane can be inspected.
    window="$command; exec \"\$SHELL\""
    if tmux has-session -t "=$session" 2>/dev/null; then
      wid=$(tmux new-window -d -P -F '#{window_id}' -t "=$session" -n claude -c "$repo" "$window")
    else
      wid=$(tmux new-session -d -P -F '#{window_id}' -s "$session" -n claude -c "$repo" "$window")
    fi

    # Which terminal shows the new window. A terminal is one tmux client,
    # and a session has one current window for all its clients, so two
    # terminals attached to the same session always show the same window
    # (seen 2026-10-29: two VS Code tabs following each other). So each
    # terminal gets a session of its own over the project's windows, a
    # session group: the first terminal the project's session itself,
    # each later one a view named <session>-<pid> that is destroyed when
    # it detaches (destroy-unattached, set only once the client is on the
    # view: set on a session with no client it destroys it at once, and
    # option commands do not take the `=name` target, 2026-10-29). The new
    # window is made with -d and selected for this client alone, so the
    # other terminals keep their window. The window colour from
    # tmux-notify.sh is the window's, so it shows in every view's status
    # line. From inside tmux a client already on the project's session or
    # one of its views just moves to the new window; one on another
    # project's session switches to the project's session, or to a fresh
    # view when that session is shown elsewhere.
    showing() { [ -n "$(tmux list-clients -t "=$session" 2>/dev/null)" ]; }
    view="$session-$$"
    if [ -n "''${TMUX:-}" ]; then
      group=$(tmux display-message -p -t "=$session" '#{session_group}')
      if [ "$(tmux display-message -p '#{session_name}')" = "$session" ] \
        || { [ -n "$group" ] && [ "$(tmux display-message -p '#{session_group}')" = "$group" ]; }; then
        exec tmux select-window -t "$wid"
      elif showing; then
        tmux new-session -d -t "$session" -s "$view"
        tmux switch-client -t "=$view:$wid"
        exec tmux set-option -t "$view" destroy-unattached on
      else
        exec tmux switch-client -t "=$session:$wid"
      fi
    elif showing; then
      tmux new-session -d -t "$session" -s "$view"
      tmux select-window -t "=$view:$wid"
      exec tmux attach-session -t "=$view" \; set-option destroy-unattached on
    else
      exec tmux attach-session -t "=$session" \; select-window -t "$wid"
    fi
  '';
}
