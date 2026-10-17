# ccode [<customer>/<repo> | <path>] [claude args...]
# Starts or attaches the project's tmux session and runs claude in a window.
#
# The project is, in order: the first argument when it names <customer>/<repo>
# under the code root or a directory under it; else $HARNESS_PROJECT, which
# the harness devenv shell exports on entry; else the repo containing the
# current directory. So inside a repo (or its worktree, or a subdirectory) a
# bare `ccode` or `ccode --worktree` does the right thing.
#
# Root: $HARNESS_CODE_ROOT (the home module exports it from harness.codeRoot),
# default below. Used identically on an enforced host and in a container
# where the root is /work.
#
# `ccode -n ...` prints the resolution and exits; tests/ccode-test.sh uses it.
{
  pkgs,
  codeRoot ? "$HOME/code/git",
}:
pkgs.writeShellApplication {
  name = "ccode";
  runtimeInputs = [ pkgs.tmux ];
  text = ''
    root="''${HARNESS_CODE_ROOT:-${codeRoot}}"; root="''${root%/}"
    usage() { echo "usage: ccode [<customer>/<repo> | <path>] [claude args]  (inside a repo under $root, the project is optional)" >&2; exit 64; }
    die() { echo "ccode: $*" >&2; exit 66; }

    # resolve <dir>: print <customer>/<repo> for a directory under the root.
    resolve() {
      local p rel a b
      p=$(cd "$1" 2>/dev/null && pwd -P) || die "no such directory: $1"
      [[ "$p" == "$root/"* ]] || die "$p is not under $root/<customer>/<repo>"
      rel="''${p#"$root/"}"
      IFS=/ read -r a b _ <<<"$rel"
      [ -n "$a" ] && [ -n "$b" ] || die "$p is not under $root/<customer>/<repo>"
      printf '%s/%s' "$a" "$b"
    }

    dry=0
    if [ "''${1:-}" = "-n" ] || [ "''${1:-}" = "--dry-run" ]; then dry=1; shift; fi

    if [ $# -ge 1 ] && [[ "$1" != -* ]]; then
      arg="$1"; shift
      if [[ "$arg" == */* && "$arg" != /* && "$arg" != .* && -d "$root/$arg" ]]; then
        project="$arg"
      elif [ -d "$arg" ]; then
        project=$(resolve "$arg")
      else
        die "no such repo: $root/$arg (give <customer>/<repo>, or a path to a repo under $root)"
      fi
    elif [ -n "''${HARNESS_PROJECT:-}" ]; then
      project="$HARNESS_PROJECT"
    elif [[ "$PWD" == "$root/"* ]]; then
      project=$(resolve "$PWD")
    else
      usage
    fi

    repo="$root/$project"
    [ -d "$repo" ] || die "no such repo: $repo"
    session="''${project//\//-}"

    if [ "$dry" = 1 ]; then
      printf 'session=%s repo=%s' "$session" "$repo"
      [ $# -eq 0 ] || printf ' args=%s' "$*"
      echo; exit 0
    fi

    printf -v command '%q ' claude "$@"
    # Keep the window open after claude exits so the pane can be inspected.
    window="$command; exec \"\$SHELL\""
    if tmux has-session -t "=$session" 2>/dev/null; then
      tmux new-window -t "=$session" -c "$repo" "$window"
    else
      tmux new-session -d -s "$session" -c "$repo" "$window"
    fi
    if [ -n "''${TMUX:-}" ]; then
      exec tmux switch-client -t "=$session"
    else
      exec tmux attach-session -t "=$session"
    fi
  '';
}
