#!/usr/bin/env bash
# env-guard: the guard hook. Registered for SessionStart, CwdChanged,
# FileChanged, ConfigChange and PreToolUse from managed settings only; the
# repo's .claude/settings.json carries no hook since 2026-10-27. The Setup
# branch below is ready but not registered. Every rule applies in every
# directory: per-org isolation comes from the Linux users (decided
# 2026-10-27), not from this hook.
#
# Two rule sets (roadmap item 14, 2026-10-28). The law binds every user,
# the jailer included: a credential read, `git commit` (unless the host
# allows local commits) and `git push`. The jail binds a
# worker, a member of WORKER_GROUP: every other rule below, and before any
# tool, that the worker's user settings carry the jail body the managed
# tree ships (jail-settings.json) and that the sandbox resolves on. A
# session as anyone else gets the law and the environment preamble, nothing
# more.
#
# Fail closed: any unexpected error exits 2, which blocks on PreToolUse and
# ConfigChange (together with onFailure = "block" in the hook registration).
# The trap needs set -E to fire inside functions, where the checks run.
# An unset variable under set -u exits non-zero without the trap.
# The same for the environment: the env-file preamble below discards what
# `direnv export` says, so before every Bash command the hook checks that
# the nearest .envrc can load (check_env) and refuses the command with the
# reason when it cannot. Needs Claude Code >= 2.1.295. lib/hooks.nix puts
# jq, direnv, grep, sed, coreutils, diffutils and findutils from the store
# first on PATH, so the guard never runs the user's copies of them.
#
# Every regex lives in a variable: bash word-splits an inline `=~` pattern
# on spaces, so `[[ x =~ a b ]]` is a syntax error.
set -Euo pipefail
PATH="@path@:${PATH:-}"
trap 'echo "env-guard: internal error, denying" >&2; exit 2' ERR

# Substituted by lib/hooks.nix from the ai-jail.* options: 0 or 1.
ALLOW_LOCAL_COMMITS="@allowLocalCommits@"
ALLOW_MEMORY_EDITS="@allowMemoryEdits@"
# The group aj bootstrap puts every worker in, and the managed tree the law,
# the jail and this hook are linked from; hook-test swaps both for its own.
WORKER_GROUP="agents"
MANAGED_DIR="/etc/claude-code"

input=$(cat)
event=$(jq -r '.hook_event_name // empty' <<<"$input")
# `cwd` follows worktrees and `cd`; CLAUDE_PROJECT_DIR stays at the start root.
cwd=$(jq -r '.cwd // empty' <<<"$input")

deny() { printf 'env-guard: %s\n' "$1" >&2; exit 2; }

# Worker or not, once. No pipeline: under pipefail an early exit could fail
# it open.
my_groups=" $(id -nG 2>/dev/null || true) "
jail=0; [[ "$my_groups" != *" $WORKER_GROUP "* ]] || jail=1

# jail_check: a worker's tools are refused unless (1) its user settings
# (CLAUDE_CONFIG_DIR, else ~/.claude) agree with the managed tree's
# jail-settings.json on every top-level key of that file (Claude Code
# rewrites the file for /model and the like, so the keys are compared, not
# the file; permissions.defaultMode, which the TUI's mode switch writes, is
# left out on both sides), and (2) the sandbox resolves as the jail writes it, since a
# project or local file outranks the user scope for a scalar: enabled true,
# allowUnsandboxedCommands false, failIfUnavailable true over user, project,
# local and managed settings. A file that does not parse refuses too. Not
# seen: a `claude --settings <file>` launch, which ajmux never passes and
# rule 6 refuses inside a session.
jail_check() {
  local ref="$MANAGED_DIR/jail-settings.json" us="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" root diff s sfiles res
  [ -r "$ref" ] || deny "worker without a jail: $ref is missing or unreadable (aj bootstrap links the managed tree)"
  [ -r "$us" ] || deny "worker without a jail: $us is missing (aj bootstrap writes the jail into it)"
  diff=$(jq -r -n --slurpfile r "$ref" --slurpfile u "$us" '($r[0] | del(.permissions.defaultMode)) as $rr | ($u[0] | del(.permissions.defaultMode)) as $uu | [$rr | keys[] | select($rr[.] != $uu[.])] | join(",")' 2>/dev/null) \
    || deny "worker without a jail: $us or $ref does not parse"
  [ -z "$diff" ] || deny "worker without a jail: $us differs from $ref at $diff (aj bootstrap rewrites it; a session must not edit it)"
  root="${CLAUDE_PROJECT_DIR:-$cwd}" sfiles=()
  for s in "$us" "$root/.claude/settings.json" "$root/.claude/settings.local.json" "$MANAGED_DIR/managed-settings.json"; do
    [ ! -e "$s" ] || sfiles+=("$s")
  done
  res=$(jq -r -n '[inputs | (try .sandbox catch null) | if type == "object" then . else {} end]
    | [ ([.[].enabled | select(. != null)] | last), ([.[].allowUnsandboxedCommands | select(. != null)] | last), ([.[].failIfUnavailable | select(. != null)] | last) ]
    | map(tostring) | join(" ")' "${sfiles[@]}" 2>/dev/null) \
    || deny "worker without a sandbox: a settings file does not parse (${sfiles[*]})"
  [ "$res" = "true false true" ] || deny "worker without a sandbox: enabled, allowUnsandboxedCommands and failIfUnavailable resolve to ($res), not (true false true); the jail in ~/.claude/settings.json sets them and a project or local file must not change them"
}

# check_env <cwd>: refuse the command unless direnv can load the .envrc
# nearest to <cwd>; a directory without one passes. `direnv status` (3 ms)
# says whether that .envrc is allowed without loading it, which covers an
# edit since the last `direnv allow`. The export itself (0.2 s warm, seconds
# after a change, measured 2026-10-23) runs only when the files direnv
# watches in a jail, or the direnv and devenv binaries, differ from
# the last good run, or when that run's DEVENV_PROFILE is gone from the
# store; the record lives under ~/.cache/ai-jailer (no record, or
# an unwritable cache, means the export runs every time). A refusal names
# the first error line and what fixes it.
check_env() {
  local st rcpath dir fp cache key profile stored out err rc first fix
  [ -d "$1" ] || return 0
  st=$(cd "$1" && direnv status --json 2>/dev/null) || deny "direnv status failed in $1 (run: direnv status)"
  rcpath=$(jq -r '.state.foundRC.path // empty' <<<"$st")
  [ -n "$rcpath" ] || return 0
  dir="${rcpath%/.envrc}"
  [ "$(jq -r '.state.foundRC.allowed // 0' <<<"$st")" = 0 ] \
    || deny "direnv export failed in $dir: $rcpath is blocked. Run \`direnv allow\` to approve its content (fix: direnv allow $dir)"
  fp=$( (cd "$dir" && stat -c '%n %Y %s %i' .envrc devenv.nix devenv.yaml devenv.lock devenv.local.nix devenv.local.yaml 2>/dev/null; readlink -f "$(command -v direnv)" "$(command -v devenv 2>/dev/null || echo /dev/null)" 2>/dev/null) ) || true
  cache="${XDG_CACHE_HOME:-$HOME/.cache}/ai-jailer/direnv-ok"
  key=$(printf '%s' "$dir" | sha256sum | cut -c1-16)
  if [ -r "$cache/$key" ]; then
    profile=$(head -n 1 "$cache/$key"); stored=$(tail -n +2 "$cache/$key")
    if [ "$stored" = "$fp" ] && { [ -z "$profile" ] || [ -e "$profile" ]; }; then return 0; fi
  fi
  # direnv skips the load when its state variables say this .envrc is
  # loaded and unchanged (a session started inside the devenv shell), so
  # they are unset: the export then evaluates every time it runs.
  out=$(mktemp)
  if err=$(cd "$dir" && env -u DIRENV_DIR -u DIRENV_FILE -u DIRENV_DIFF -u DIRENV_WATCHES direnv export json 2>&1 >"$out"); then rc=0; else rc=$?; fi
  if [ "$rc" != 0 ] || grep -q 'is blocked' <<<"$err"; then
    rm -f "$out"
    first=$(grep -i -m1 'error' <<<"$err" || grep -v '^$' <<<"$err" | tail -n 1 || true)
    # The template .envrc refuses to load while a devenv.local.* exists
    # (2026-10-26); `devenv shell` skips the .envrc and would import it.
    if grep -q 'is blocked' <<<"$err"; then fix="direnv allow $dir"
    elif grep -q 'is refused in a jail' <<<"$err"; then fix="remove the devenv.local file from your own terminal; it is not the agent's to remove"
    else fix="the devenv error (devenv shell in $dir shows it)"; fi
    deny "direnv export failed in $dir: ${first:-exit $rc} (fix: $fix)"
  fi
  # The export lists what differs from this environment: a profile already
  # in it (the session's own devenv shell) is the current one.
  profile=$(jq -r '.DEVENV_PROFILE // empty' "$out" 2>/dev/null) || profile=""
  [ -n "$profile" ] || profile="${DEVENV_PROFILE:-}"
  rm -f "$out"
  { mkdir -p "$cache" && printf '%s\n%s\n' "$profile" "$fp" > "$cache/$key"; } 2>/dev/null || true
  return 0
}

case "$event" in
  SessionStart|CwdChanged|FileChanged|Setup)
    [ -n "${CLAUDE_ENV_FILE:-}" ] || exit 0
    # A worktree .envrc is auto-allowed only when byte-identical to the main
    # checkout's .envrc, and only if that one is itself allowed. Never use
    # direnv.toml whitelist.prefix for this: it is path-only and never re-prompts.
    if [[ "$cwd" == */.claude/worktrees/* && -f "$cwd/.envrc" ]]; then
      main="${cwd%%/.claude/worktrees/*}"
      if cmp -s "$main/.envrc" "$cwd/.envrc" \
         && (cd "$main" && direnv status --json 2>/dev/null) \
            | jq -e --arg p "$main/.envrc" '.state.foundRC.path==$p and .state.foundRC.allowed==0' >/dev/null; then
        (cd "$cwd" && direnv allow) || true
      fi
    fi
    # Executed by Claude Code as a preamble before every Bash command, in that
    # command's cwd. Per-command evaluation is robust to EnterWorktree and to
    # devenv.nix edits; the find line cleans the .devenv/shell-*.sh files that
    # every `devenv direnv-export` leaves behind (decision 7.3 of a design
    # brief not kept in this repo; changelog 2026-10-22 refers to it).
    # direnv and devenv by store path, resolved here outside the sandbox (the
    # user's devenv, the hook's direnv): with the read fence on,
    # `~/.nix-profile` (a symlink) is not mounted back into the sandbox, so
    # the profile's bin directory is off PATH there (live, 2026-10-21).
    # devenv creates `$XDG_RUNTIME_DIR/devenv-<hash>` before it evaluates and
    # the sandbox mounts /run/user/<uid> read-only, so the export runs with
    # the sandbox's TMPDIR as its runtime directory (devenv ignores
    # DEVENV_RUNTIME). The command's own XDG_RUNTIME_DIR is untouched: direnv
    # exports only what the devenv shell changed (live, 2026-10-22).
    tool_path=""
    for t in direnv devenv; do
      if p=$(command -v "$t"); then tool_path="$tool_path${tool_path:+:}$(dirname "$(readlink -f "$p")")"; fi
    done
    {
      [ -z "$tool_path" ] || printf 'export PATH="%s:$PATH"\n' "$tool_path"
      cat <<'ENV'
if command -v direnv >/dev/null 2>&1; then eval "$(XDG_RUNTIME_DIR="${TMPDIR:-/tmp}" direnv export bash 2>/dev/null)"; fi
if [ -d .devenv ]; then find .devenv -maxdepth 1 -name 'shell-*.sh' -mmin +10 -delete 2>/dev/null; fi
ENV
    } > "$CLAUDE_ENV_FILE"
    exit 0 ;;

  ConfigChange)
    # Jail only: the jailer changes its own settings (/model writes
    # ~/.claude/settings.json).
    [ "$jail" = 1 ] || exit 0
    src=$(jq -r '.source // empty' <<<"$input")
    case "$src" in
      # .claude/settings.local.json outranks the repo's settings.json for
      # scalar keys (sandbox.enabled, defaultMode) and is applied live.
      user_settings|policy_settings|local_settings) deny "config change to $src blocked" ;;
    esac
    exit 0 ;;

  PreToolUse)
    [ "$jail" = 0 ] || jail_check
    tool=$(jq -r '.tool_name // empty' <<<"$input")
    case "$tool" in
      Edit|Write|NotebookEdit|MultiEdit)
        # Jail only. The law's credential reads are deny rules (a Read deny
        # also blocks Edit and Write, 2.1.228+), not a path check here.
        [ "$jail" = 1 ] || exit 0
        f=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")
        # The patterns below are literal: make the path absolute and fold `.`
        # and `..` first. Both the path as named (`-s`, so a home-manager
        # ~/.bashrc, a link into the store, still matches its own name) and
        # its target (a link in the repo to ~/.bashrc) must pass.
        [[ "$f" == /* ]] || f="$cwd/$f"
        # The one carve-out under ~/.claude is auto-memory, when the host
        # allows it, and only the session's own project's: another repo's
        # next session loads its memory unreviewed, with its own
        # allowMemoryEdits off. Claude Code names the directory after the
        # path with every character outside [a-zA-Z0-9] made `-`, case kept;
        # past 200 characters it truncates and appends a hash this hook does
        # not compute (code.claude.com/docs/en/sessions, "Where transcripts
        # are stored"; read in the 2.1.308 binary, 2026-10-26). No
        # CLAUDE_PROJECT_DIR, or a slug past 200, means no carve-out. A
        # session started in a subdirectory or a worktree keeps its memory
        # under the repository's main root (docs/en/memory), which this
        # does not match: refused, not widened.
        own_memory=
        if [ "$ALLOW_MEMORY_EDITS" = 1 ] && [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
          slug="${CLAUDE_PROJECT_DIR//[^a-zA-Z0-9]/-}"
          [ "${#slug}" -gt 200 ] || own_memory="$HOME/.claude/projects/$slug/memory"
        fi
        check_edit() { # check_edit <absolute path>
          if [ -n "$own_memory" ]; then
            case "$1" in
              "$own_memory"/*) return 0 ;;
            esac
          fi
          # The user's own Claude and Nix config, and the files listed below
          # that run code at their next shell, git or tmux start, outside the
          # sandbox. The same list as userConfig in lib/deny-rules.nix; change both.
          case "$1" in
            "$HOME"/.claude/*|"$HOME"/.claude.json|"$HOME"/.config/*|"$HOME"/.ssh/*|\
            "$HOME"/.bashrc|"$HOME"/.bash_profile|"$HOME"/.bash_login|"$HOME"/.profile|\
            "$HOME"/.zshrc|"$HOME"/.zprofile|"$HOME"/.zshenv|"$HOME"/.zlogin|\
            "$HOME"/.gitconfig|"$HOME"/.tmux.conf|"$HOME"/.bashrc.d/*|"$HOME"/.local/bin/*)
              deny "edit of $1 is forbidden (user config)" ;;
          esac
          case "$1" in
            */.claude/settings*.json|*/.claude/hooks/*|*/.claude/skills/*|*/.claude-plugin/*|\
            */devenv.nix|*/devenv.yaml|*/devenv.lock|*/devenv.local.*|*/.envrc|*/.env|*/.env.*|*.tfvars|*.tfvars.json|*.tfstate|\
            */.git/hooks/*|*/.git/config)
              deny "edit of $1 is forbidden (config/env/credentials/plugin)" ;;
          esac
        }
        check_edit "$(realpath -sm -- "$f")"
        check_edit "$(realpath -m -- "$f")"
        exit 0 ;;

      Bash)
        cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
        # Normalise: lowercase, strip backslashes, collapse whitespace, strip
        # quotes. Catches `bash -c '...'`, `env X=1 git push`, `git 'push'`,
        # `git -C . push`, `git pu\sh` and a backslash-newline continuation.
        # `nc` keeps case, for the few flags where case is the meaning.
        nc=$(printf '%s' "$cmd" | tr -d '\\' | tr -s '[:space:]' ' ' | tr -d "'\"")
        n="${nc,,}"
        b='(^|[ ;&|(])'       # start of a (sub)command
        e='( |$)'             # end of a word

        # --- the law: everyone, the jailer included ------------------------
        # L1. `git commit` (unless the host allows local commits) and `git
        # push`: `/usr/bin/git`, `git -C . push`, `git --git-dir=.git push`.
        law_git='push'; [ "$ALLOW_LOCAL_COMMITS" = 1 ] || law_git='commit|push'
        re="(^|[^a-z0-9_.-])git( +-[-a-z]+(=[^ ]*| +[^ ]+)?)* +($law_git)$e"
        [[ "$n" =~ $re ]] && deny "git commit/push blocked: the human commits and pushes"
        # L2. credential reads. cred_files: in-repo secrets, the user's own
        # Claude credentials, and the home-directory credential stores the
        # law's Read rules name (ssh, the GitHub tokens on disk, Azure's
        # token cache), which an unsandboxed jailer session has no sandbox
        # to hide. A path matching cred_files anywhere blocks, unless the
        # whole command is one simple command whose verb cannot show
        # content: one line (the normaliser folds newlines, so the raw
        # command is checked), no pipe, no `$(`, backtick or `>(`
        # substitution, no input redirection, and none of the options that
        # read file names from a file, whose errors echo each line (`file
        # -f`, `--files0-from`, `--pathspec-from-file`). A reader list
        # cannot be completed (dd, tr, perl, `git show <ref>:.env`, a bare
        # `< .env`).
        cred_files='(\.env([^a-z0-9]|$)|\.tfvars|\.tfstate|\.claude/\.credentials\.json|\.claude\.json|\.credentials\.json|\.ssh/|\.git-credentials|\.config/gh/|\.azure/)'
        # `ssh -i ~/.ssh/<key> host` uses a key without showing it (scp and
        # rsync would copy it, so they are not here).
        harmless='^(ls|stat|file|du|wc|rm|git rm|test|\[|echo|printf|touch|ssh)( [^;&|<$`(]*)?$'
        list_opts='--files0-from|--files-from|--pathspec-from-file|(^| )file( +-[a-z]+)* +-[a-z]*f'
        if [[ "$n" =~ $cred_files ]]; then
          safe=0
          [[ "$cmd" != *$'\n'* ]] && [[ "$n" =~ $harmless ]] && ! [[ "$n" =~ $list_opts ]] && safe=1
          [ "$safe" = 1 ] || deny "credential file access blocked"
        fi
        # The jailer: the law, then the environment check (rule 8).
        if [ "$jail" = 0 ]; then check_env "$cwd"; exit 0; fi

        # --- the jail: a worker ----------------------------------------------
        # 1. git history and index writes
        git_ops='push|reset|rebase|merge|cherry-pick|revert|am|filter-branch|filter-repo|reflog +(expire|delete)|branch +-[dm]|branch +(-f|--force)|tag +-d|tag +(-f|--force)|stash +(drop|clear|pop)|checkout( +[^ ;&|]+)* +--|checkout +(-f|--force|\.[^ ]*)|switch +(-f|--force|--discard-changes)|worktree +remove( +[^ ;&|]+)* +(-f|--force)|restore|clean|gc|prune|update-ref|symbolic-ref|notes|commit-tree'
        [ "$ALLOW_LOCAL_COMMITS" = 1 ] || git_ops="commit|$git_ops"
        # `/usr/bin/git`, `git -C . push`, `git --git-dir=.git push`.
        re="(^|[^a-z0-9_.-])git( +-[-a-z]+(=[^ ]*| +[^ ]+)?)* +($git_ops)$e"
        [[ "$n" =~ $re ]] && deny "git history/index write blocked: stage with git add, branch with git switch -c; revert a file with git show HEAD:<path> > <path>"
        # `-C`/`-B` reset an existing branch; lowercased they read as the harmless `-c`/`-b`.
        re='(^|[^a-zA-Z0-9_.-])git( +[^ ;&|]+)* +(switch +-C|checkout +-B)( |$)'
        [[ "$nc" =~ $re ]] && deny "git history/index write blocked: stage with git add, branch with git switch -c; revert a file with git show HEAD:<path> > <path>"
        # `git checkout <ref> <path>...` discards edits to those paths; the
        # branch-creating forms take a start point and are the exception.
        re='(^|[^a-z0-9_.-])git( +-[-a-z]+(=[^ ]*| +[^ ]+)?)* +checkout( +-[^ ;&|]+)* +[^- ;&|][^ ;&|]* +[^- ;&|][^ ;&|]*'
        creates='checkout( +[^ ;&|]+)* +(-b|--orphan|-t|--track)( |$)'
        [[ "$n" =~ $re ]] && ! [[ "$n" =~ $creates ]] && deny "git history/index write blocked: stage with git add, branch with git switch -c; revert a file with git show HEAD:<path> > <path>"
        re='git_dir=|git_work_tree=|git_index_file=|git_config_global=|git_config_system='
        [[ "$n" =~ $re ]] && deny "git env redirect blocked"

        # 2. cloud and infrastructure writes
        re="(^|[^a-z])(terraform|tofu|terragrunt)( +-[^ ]+)* +(apply|destroy|import|taint|untaint|state|force-unlock|workspace +(new|delete|select))$e"
        [[ "$n" =~ $re ]] && deny "terraform write blocked: plan/validate only; propose apply/state commands to the human"
        re="(^|[^a-z])az .* (create|delete|update|set|start|stop|restart|deploy|purge|assign|remove|rotate|regenerate|invoke|run|import|restore|scale)$e"
        [[ "$n" =~ $re ]] && deny "az write blocked: read/list/show only; propose write commands to the human"
        re='(^|[^a-z])az +(deployment|group +(create|delete)|rest +.*--method +(post|put|patch|delete))'
        [[ "$n" =~ $re ]] && deny "az deployment/rest write blocked: read/list/show only; propose deployment and rest write commands to the human"
        re='(^|[^a-z])(func +azure +functionapp +publish|pulumi +(up|destroy)|bicep +publish)'
        [[ "$n" =~ $re ]] && deny "deploy blocked"

        # 3. credential operations (the credential files are the law's, L2)
        re='(^|[^a-z])az +(login|logout|account +(set|clear|get-access-token)|ad +sp +credential|keyvault +(secret|key|certificate) +(show|download|list|backup))'
        [[ "$n" =~ $re ]] && deny "credential operation blocked"

        # 4. system and config
        re="(^|[^a-z])(sudo|doas|pkexec|su|run0)$e"
        [[ "$n" =~ $re ]] && deny "privilege escalation blocked"
        re='(^|[^a-z])(nix +(profile|upgrade-nix|registry|store +(gc|delete|optimise))|nix-env|nix-collect-garbage|nixos-rebuild|nh +(os +(switch|boot|test)|home +switch)|nix-channel|home-manager +switch|systemctl|journalctl +--vacuum|wsl\.exe|wslconfig)'
        [[ "$n" =~ $re ]] && deny "system change blocked"
        re="$b(powershell|pwsh|cmd)(\.exe)?( |$)|$b[^ ]*\.exe( |$)|/mnt/c/"
        [[ "$n" =~ $re ]] && deny "Windows executable blocked"
        # `direnv allow` approves an .envrc, and the env-file preamble then
        # loads it, with the devenv.nix it uses, before every later Bash
        # command. The sandbox keeps direnv's allow list read-only; without
        # the sandbox only this rule stops a session approving its own edit
        # (changelog 2026-10-26). `grant` is a third name for allow, and
        # `edit` allows once the editor exits (`direnv help`, 2.38.2).
        re="$b"'direnv +(allow|permit|grant|edit)'"$e"
        [[ "$n" =~ $re ]] && deny "direnv allow blocked: the human approves .envrc changes"
        # Shell-side writes to the project setup files the Edit tool refuses.
        # The user-config files the Edit check refuses are not matched here;
        # in a work repo the sandbox's write confinement covers them.
        config_files='(devenv\.(nix|yaml|lock|local)|\.envrc|\.claude/|\.claude-plugin|\.git/hooks|\.git/config|\.config/nix|\.config/direnv)'
        # `2>/dev/null`, `>&2` and friends write no file, so they are dropped;
        # every `>` left counts as a write (`1>`, `2>`, `&>`, `>>` included).
        # Only `>/dev/null` with no space is dropped: `> /dev/null` counts.
        w=$(printf '%s' "$n" | sed -E 's#[0-9]*>&[0-9]+##g; s#[0-9]*>/dev/null##g')
        writers="(&?>|$b(tee|mv|cp|rm|ln|install|truncate|chmod|chattr|patch|dd)$e|sed +-[a-z]*i|perl +-[a-z]*i)"
        if [[ "$n" =~ $config_files ]] && [[ "$w" =~ $writers ]]; then
          deny "shell write to config file blocked"
        fi

        # 5. plugin and mod loading
        re='(^|[^a-z])claude +plugin +(install|marketplace|enable|update|add)'
        [[ "$n" =~ $re ]] && deny "plugin install blocked"
        re='--plugin-(dir|url)|claude_code_plugin_dirs=|--mcp-config|--agents( |=)'
        [[ "$n" =~ $re ]] && deny "plugin sideload blocked"
        # The jail lives in ~/.claude/settings.json; a child session pointed
        # elsewhere would start without it (jail_check reads the same variable).
        re='claude_config_dir='
        [[ "$n" =~ $re ]] && deny "CLAUDE_CONFIG_DIR blocked: the jail is in ~/.claude/settings.json"

        # 6. nested sessions that would skip the rules. These flags replace
        # or bypass settings for the child session (`--bare` skips every
        # hook); `--add-dir` widens the child's working
        # directories, which the sandbox lets it write. `ajmux [<project>]`
        # hands the rest to `claude`. Arguments stop at a command separator
        # so a flag in a later command does not count; one inside quotes or
        # after a backslash is text (`-p "a; b" --bare`), as is the `&` of
        # `2>&1` and `&>`, so this rule reads the command with those turned
        # into `_`, which only adds matches. A renamed copy of the binary
        # gets past this; the sandbox is the layer for that.
        launcher='claude|ajmux'
        q=$(printf '%s' "$cmd" | jq -Rsj 'gsub("(?<q>\"(\\\\.|[^\"\\\\])*\"|\\x27[^\\x27]*\\x27|\\\\.|>&|&>)"; .q | gsub("[;&|]"; "_"))' | tr -d '\\' | tr -s '[:space:]' ' ' | tr -d "'\"")
        re="(^|[^a-z])($launcher)( +[^ ;&|]+)* +--(bare|setting-sources|settings|permission-mode|dangerously-skip-permissions|allow-dangerously-skip-permissions|add-dir)( |=|$)"
        [[ "${q,,}" =~ $re ]] && deny "claude launch flag blocked"

        # 7. the tmux server (roadmap 2.8a). It runs outside
        # the sandbox and allowAllUnixSockets reaches its socket, so most
        # tmux commands run something there with no sandbox and no hook
        # (`run-shell`, `new-window`, `send-keys` into another session's
        # pane). Allowed: the read-only commands in tmux_ro by full name or
        # alias (tmux also takes unique prefixes; those are refused), and
        # display-message only with -p and without -I (-I writes stdin into
        # a pane). A word after `tmux` that cannot be a tmux command name
        # (`grep tmux docs/`) is not a tmux call; one that could become one
        # by expansion is refused. Bare `tmux` (new-session) passes: without
        # a terminal it exits before creating anything (tmux 3.8, live
        # 2026-10-26). Refused in a call: -C (control mode reads commands
        # from stdin); an argument ending in `;`, tmux's own command
        # separator (`tmux has -t s ';' display -p hi` ran both, live
        # 2026-10-26), which reaches tmux only quoted or escaped, so this
        # rule reads a quoted or escaped separator as \x01; `#(`, a format
        # job the server runs (not seen to run from `display-message -p` on
        # tmux 3.8, refused anyway); and `$`, backticks and globs in the
        # arguments, which can expand to a `;`. Text only: a script or
        # `python` on the socket gets past this; roadmap 2.8b is the socket.
        tm=$(printf '%s' "$cmd" | jq -Rsj 'gsub("(?<q>\"(\\\\.|[^\"\\\\])*\"|\\x27[^\\x27]*\\x27|\\\\.|>&|&>)"; .q | if test("^[\"\\x27\\\\]") then gsub("[;&|]"; "\u0001") else gsub("&"; "_") end)' | tr -d '\\' | tr -s '[:space:]' ' ' | tr -d "'\"" | tr '<>' '  ')
        tmux_ro='^(ls|list-(sessions|windows|panes|clients|buffers|keys|commands)|lsw|lsp|lsc|lsb|lsk|lscm|has|has-session|show|show-(options|window-options|environment|buffer|messages|hooks)|showw|showenv|showb|showmsgs|display|display-message)$'
        call='(^|[^a-zA-Z0-9_.-])tmux( |$)(.*)'
        name='^[a-z-]+$'
        name_exp=$'[\x01$`?*[{]'
        arg_exp=$'[\x01$`?*[]'
        control='^-[^cfLST]*C'
        takes_arg='^-[^cfLST]*[cfLST]$'
        print='(^| )-[aClNpv]*p[aClNpv]*( |$)'
        input='(^| )-[a-zA-Z]*I'
        rest="$tm"
        while [[ "$rest" =~ $call ]]; do
          rest="${BASH_REMATCH[3]}"
          read -ra words <<<"${rest%%[;&|)\`]*}"
          sub="" i=0
          while [ "$i" -lt "${#words[@]}" ]; do
            w="${words[$i]}"; i=$((i + 1))
            [[ "$w" == -* ]] || { sub="$w"; break; }
            [[ "$w" =~ $control ]] && deny "tmux -C blocked: control mode reads tmux commands from stdin"
            [[ "$w" =~ $takes_arg ]] && i=$((i + 1))
          done
          [ -n "$sub" ] || continue
          if ! [[ "$sub" =~ $name ]]; then
            [[ "$sub" =~ $name_exp ]] && deny "tmux call blocked: its command word could expand to a tmux command"
            continue
          fi
          [[ "$sub" =~ $tmux_ro ]] || deny "tmux $sub blocked: the tmux server runs outside the sandbox (read-only: ls, list-*, has-session, show-*, display-message -p, by full name or alias)"
          a="${words[*]:i}"
          [[ "$a" =~ $arg_exp || "$a" == *'#('* ]] && deny "tmux $sub blocked: \$, backticks, globs, #( and a quoted ; are refused in tmux arguments"
          if [[ "$sub" == display* ]] && { ! [[ "$a" =~ $print ]] || [[ "$a" =~ $input ]]; }; then
            deny "tmux $sub blocked: only display-message -p, without -I"
          fi
        done

        # 8. the environment the command is about to run in must load (the
        # env-file preamble above is fail-open on its own).
        check_env "$cwd"
        exit 0 ;;
    esac
    exit 0 ;;
esac
exit 0
