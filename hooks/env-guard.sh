#!/usr/bin/env bash
# env-guard: the guard hook. Registered for SessionStart, CwdChanged,
# FileChanged, ConfigChange and PreToolUse, from managed settings on a
# managed host and from the repo's .claude/settings.json (devenv module)
# everywhere; the Setup branch below is ready but not registered.
#
# Fail closed: any unexpected error exits 2, which blocks on PreToolUse and
# ConfigChange (together with onFailure = "block" in the hook registration).
# Needs Claude Code >= 2.1.295. lib/hooks.nix puts jq, direnv and
# coreutils from the store first on PATH, so the guard never runs the
# user's copies of them.
#
# Every regex lives in a variable: bash word-splits an inline `=~` pattern
# on spaces, so `[[ x =~ a b ]]` is a syntax error.
set -uo pipefail
PATH="@path@:${PATH:-}"
trap 'echo "env-guard: internal error, denying" >&2; exit 2' ERR

# Substituted by lib/hooks.nix from the harness.* options: 0 or 1, and a
# colon-separated list where `~` means $HOME and empty means everywhere.
ALLOW_LOCAL_COMMITS="@allowLocalCommits@"
ALLOW_MEMORY_EDITS="@allowMemoryEdits@"
ENFORCEMENT_ROOTS="@enforcementRoots@"

input=$(cat)
event=$(jq -r '.hook_event_name // empty' <<<"$input")
# `cwd` follows worktrees and `cd`; CLAUDE_PROJECT_DIR stays at the start root.
cwd=$(jq -r '.cwd // empty' <<<"$input")

deny() { printf 'env-guard: %s\n' "$1" >&2; exit 2; }

# Project rules apply when there are no roots, when cwd is unknown (fail
# closed), when cwd is under a root, or when the call names a path under a
# root (`git -C ~/code/git/x push` from a session started elsewhere). The
# universal rules apply regardless.
in_scope=1
roots=()
if [ -n "$ENFORCEMENT_ROOTS" ] && [ -n "$cwd" ]; then
  in_scope=0
  IFS=: read -ra raw <<<"$ENFORCEMENT_ROOTS"
  for r in "${raw[@]}"; do
    r="${r/#\~/$HOME}"; roots+=("${r%/}")
  done
  under_root() { # under_root <path>
    local p="$1" r
    for r in "${roots[@]}"; do [[ "$p" == "$r" || "$p" == "$r/"* ]] && return 0; done
    return 1
  }
  mentions_root() { # mentions_root <normalised command text>
    local t="$1" r
    for r in "${roots[@]}"; do
      [[ "$t" == *"${r,,}"* || "$t" == *"~${r#"$HOME"}"* ]] && return 0
    done
    return 1
  }
  under_root "$cwd" && in_scope=1
fi

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
    # every `devenv direnv-export` leaves behind (decision 7.3 in the brief).
    # direnv and devenv by store path, resolved here outside the sandbox (the
    # user's devenv, the hook's direnv): with the read fence on,
    # `~/.nix-profile` (a symlink) is not mounted back into the sandbox, so
    # the profile's bin directory is off PATH there (live, 2026-10-21).
    tool_path=""
    for t in direnv devenv; do
      if p=$(command -v "$t"); then tool_path="$tool_path${tool_path:+:}$(dirname "$(readlink -f "$p")")"; fi
    done
    {
      [ -z "$tool_path" ] || printf 'export PATH="%s:$PATH"\n' "$tool_path"
      cat <<'ENV'
if command -v direnv >/dev/null 2>&1; then eval "$(direnv export bash 2>/dev/null)"; fi
if [ -d .devenv ]; then find .devenv -maxdepth 1 -name 'shell-*.sh' -mmin +10 -delete 2>/dev/null; fi
ENV
    } > "$CLAUDE_ENV_FILE"
    exit 0 ;;

  ConfigChange)
    src=$(jq -r '.source // empty' <<<"$input")
    case "$src" in
      user_settings|policy_settings) deny "config change to $src blocked" ;;
      # .claude/settings.local.json outranks the repo's settings.json for
      # scalar keys (sandbox.enabled, defaultMode) and is applied live, so
      # under the roots a change to it is refused (project rule).
      local_settings) [ "$in_scope" = 1 ] && deny "config change to $src blocked" ;;
    esac
    exit 0 ;;

  PreToolUse)
    tool=$(jq -r '.tool_name // empty' <<<"$input")
    case "$tool" in
      Edit|Write|NotebookEdit|MultiEdit)
        f=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")
        [ "$in_scope" = 1 ] || { under_root "$f" && in_scope=1; }
        # The one carve-out under ~/.claude is auto-memory, when the host
        # allows it; the path must be literal (no `..`) so it cannot reach a
        # sibling directory.
        if [ "$ALLOW_MEMORY_EDITS" = 1 ] && [[ "$f" != *"/../"* && "$f" != *"/.." ]]; then
          case "$f" in
            "$HOME"/.claude/projects/*/memory/*) exit 0 ;;
          esac
        fi
        case "$f" in
          "$HOME"/.claude/*|"$HOME"/.claude.json|"$HOME"/.bashrc|"$HOME"/.profile|"$HOME"/.config/nix/*|"$HOME"/.config/direnv/*)
            deny "edit of $f is forbidden (user config)" ;;
        esac
        if [ "$in_scope" = 1 ]; then
          case "$f" in
            */.claude/settings*.json|*/.claude/hooks/*|*/.claude/skills/*|*/.claude-plugin/*|\
            */devenv.nix|*/devenv.yaml|*/devenv.lock|*/devenv.local.*|*/.envrc|*/.env|*/.env.*|*.tfvars|*.tfvars.json|*.tfstate|\
            */.git/hooks/*|*/.git/config)
              deny "edit of $f is forbidden (config/env/credentials/plugin)" ;;
          esac
        fi
        exit 0 ;;

      Bash)
        cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
        # Normalise: lowercase, strip backslashes, collapse whitespace, strip
        # quotes. Catches `bash -c '...'`, `env X=1 git push`, `git 'push'`,
        # `git -C . push`, `git pu\sh` and a backslash-newline continuation.
        n=$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]' | tr -d '\\' | tr -s '[:space:]' ' ' | tr -d "'\"")
        [ "$in_scope" = 1 ] || { mentions_root "$n" && in_scope=1; }
        b='(^|[ ;&|(])'       # start of a (sub)command
        e='( |$)'             # end of a word

        # 1. git history and index writes (project rule)
        if [ "$in_scope" = 1 ]; then
        git_ops='push|reset|rebase|merge|cherry-pick|revert|am|filter-branch|filter-repo|reflog +(expire|delete)|branch +-[dm]|tag +-d|stash +(drop|clear|pop)|checkout +--|restore|clean|gc|prune|update-ref|symbolic-ref|notes|commit-tree'
        [ "$ALLOW_LOCAL_COMMITS" = 1 ] || git_ops="commit|$git_ops"
        re="(^|[^a-z0-9_./-])git( +-[-a-z]+( +[^ ]+)?)* +($git_ops)$e"
        [[ "$n" =~ $re ]] && deny "git history/index write blocked"
        re='git_dir=|git_work_tree=|git_index_file=|git_config_global=|git_config_system='
        [[ "$n" =~ $re ]] && deny "git env redirect blocked"
        fi

        # 2. cloud and infrastructure writes (project rule)
        if [ "$in_scope" = 1 ]; then
        re="(^|[^a-z])(terraform|tofu|terragrunt)( +-[^ ]+)* +(apply|destroy|import|taint|untaint|state|force-unlock|workspace +(new|delete|select))$e"
        [[ "$n" =~ $re ]] && deny "terraform write blocked"
        re="(^|[^a-z])az .* (create|delete|update|set|start|stop|restart|deploy|purge|assign|remove|rotate|regenerate|invoke|run|import|restore|scale)$e"
        [[ "$n" =~ $re ]] && deny "az write blocked"
        re='(^|[^a-z])az +(deployment|group +(create|delete)|rest +.*--method +(post|put|patch|delete))'
        [[ "$n" =~ $re ]] && deny "az deployment/rest write blocked"
        re='(^|[^a-z])(func +azure +functionapp +publish|pulumi +(up|destroy)|bicep +publish)'
        [[ "$n" =~ $re ]] && deny "deploy blocked"
        fi

        # 3. credentials (universal)
        re='(^|[^a-z])az +(login|logout|account +(set|clear|get-access-token)|ad +sp +credential|keyvault +(secret|key|certificate) +(show|download|list|backup))'
        [[ "$n" =~ $re ]] && deny "credential operation blocked"
        cred_files='(\.env([^a-z0-9]|$)|\.tfvars|\.tfstate|\.azure/|\.terraform\.d/|credentials\.json|\.claude\.json|\.credentials|/\.ssh/|id_(rsa|ed25519)|\.netrc|\.npmrc|\.pypirc)'
        readers="$b(cat|less|more|head|tail|sed|awk|cut|strings|od|xxd|base64|grep|rg|jq|yq|cp|mv|scp|rsync|curl|wget|python3?|node|source|\.)$e"
        if [[ "$n" =~ $cred_files ]] && [[ "$n" =~ $readers ]]; then
          deny "credential file access blocked"
        fi

        # 4. system and config (universal)
        re="(^|[^a-z])(sudo|doas|pkexec|su)$e"
        [[ "$n" =~ $re ]] && deny "privilege escalation blocked"
        re='(^|[^a-z])(nix +(profile|upgrade-nix|registry|store +(gc|delete|optimise))|nix-env|nix-collect-garbage|nixos-rebuild|nix-channel|home-manager +switch|systemctl|journalctl +--vacuum|wsl\.exe|wslconfig)'
        [[ "$n" =~ $re ]] && deny "system change blocked"
        re="$b(powershell|pwsh|cmd)(\.exe)?( |$)|$b[^ ]*\.exe( |$)|/mnt/c/"
        [[ "$n" =~ $re ]] && deny "Windows executable blocked"
        # Shell-side writes to the files the Edit tool may not touch (project rule).
        if [ "$in_scope" = 1 ]; then
        config_files='(devenv\.(nix|yaml|lock|local)|\.envrc|\.claude/|\.claude-plugin|\.git/hooks|\.git/config|\.config/nix|\.config/direnv)'
        writers="((^|[^0-9&<])>|$b(tee|mv|cp|rm|ln|install|truncate|chmod|chattr|patch|dd)$e|sed +-[a-z]*i|perl +-[a-z]*i)"
        if [[ "$n" =~ $config_files ]] && [[ "$n" =~ $writers ]]; then
          deny "shell write to config file blocked"
        fi
        fi

        # 5. plugin and mod loading (universal)
        re='(^|[^a-z])claude +plugin +(install|marketplace|enable|update|add)'
        [[ "$n" =~ $re ]] && deny "plugin install blocked"
        re='--plugin-(dir|url)|claude_code_plugin_dirs=|--mcp-config|--agents( |=)'
        [[ "$n" =~ $re ]] && deny "plugin sideload blocked"

        # 6. nested sessions that would skip the repo's rules (project rule).
        # Without managed settings the repo file is the only rule source, and
        # these flags replace or bypass it for the child session (`--bare`
        # skips every hook). Arguments stop at a command separator so a flag
        # mentioned in a later command does not count. A renamed copy of the
        # binary gets past this; the sandbox is the layer for that.
        if [ "$in_scope" = 1 ]; then
        re="(^|[^a-z])claude( +[^ ;&|]+)* +--(bare|setting-sources|settings|permission-mode|dangerously-skip-permissions|allow-dangerously-skip-permissions)( |=|$)"
        [[ "$n" =~ $re ]] && deny "claude launch flag blocked"
        fi
        exit 0 ;;
    esac
    exit 0 ;;
esac
exit 0
