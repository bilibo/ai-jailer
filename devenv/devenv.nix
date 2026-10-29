# Every jail (a repo under ai-jailer) imports this from devenv.yaml:
#
#   inputs:
#     ai-jailer:
#       url: github:bilibo/ai-jailer  (or path:..., flake: false)
#   imports:
#     - ai-jailer/devenv
#
# It writes the repo's .claude/settings.json, the cell, or project layer
# (`projectSettings` in lib/settings.nix): the allow rules from `settings`,
# the deny rules from `extraDeny`, the project's domains, the read fence
# when on, literal `denyWrite` entries for the repo's own settings, hooks
# and git files under the checkout, and a few scalars repeated as a belt,
# never `sandbox.enabled`. The law (credential reads, `git push`, the
# hooks) comes from the host's managed settings (`managedSettingsPath`),
# and the jail (the full deny set, the sandbox with its credential and
# network lists) from the worker user's own settings, written by `aj
# bootstrap` (roadmap item 14, 2026-10-28); on a host without the managed
# file the repo has none of them, and every shell entry says so.
#
# `ai-jail.enable = false` is the repo owner's off switch: no settings file
# (devenv's files cleanup removes the link it wrote before), so none of the
# project layer, and no AI_JAILER_* exports; a notice at every shell entry
# says so. The packages stay: they are tools, not rules. A worker's session
# cannot set it: the jail's deny rules and hook rules refuse its edits to
# devenv.nix, the same as for every other option here.
#
# direnv runs `devenv direnv-export` for humans and for every Claude Code
# Bash command alike, so everything in enterShell happens on both paths.
# Project tools (az, terraform, ...) belong in the project's own devenv.nix
# or in devenv-base, not here.
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.ai-jail;
  jailerLib = import ../lib { inherit lib; };
  projectName = if config.name == null then "project" else config.name;

  ajmux = import ../pkgs/ajmux.nix { inherit pkgs; };
  # nixpkgs' claude-code without the LD_LIBRARY_PATH its wrapper leaks into
  # every command (pkgs/claude-code.nix).
  claudeCode = import ../pkgs/claude-code.nix { inherit pkgs; };
in
{
  options.ai-jail = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        The project layer for this repo. `false` turns it off: no
        .claude/settings.json (devenv removes the one it wrote before), so
        none of the repo's allow rules, extra deny rules, domains or read
        fence, no AI_JAILER_* exports, and a one-line notice at shell entry.
        The packages (ajmux, claudeCode.enable's) stay. The host's managed
        settings apply either way.
      '';
    };

    allowConnectors = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Let the claude.ai account's connectors (Gmail, Drive, Notion, ...) load in sessions in this repo. They are MCP servers outside the Bash sandbox. A user or managed `false` wins over a `true` here.";
    };

    platform = lib.mkOption {
      type = lib.types.enum [
        "linux"
        "wsl"
      ];
      default = "linux";
      description = "Host kind the repo is used on. `wsl` adds the Windows-interop entries to the sandbox.";
    };

    extraDeny = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "Bash(az devops *)" ];
      description = "Additional permission deny rules, the repo file's `permissions.deny`; deny lists merge across scopes, so they add to the managed set.";
    };

    readFence = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Hide the rest of your home directory from sandboxed commands:
        `denyRead ["~/"]` plus `allowRead` for this repo and the paths the
        devenv shell entry needs (lib/settings.nix). Sibling repos and
        `~/.claude/.credentials.json` become unreadable from the shell. Add
        what the project itself reads under `$HOME` with `extraAllowRead`.
      '';
    };

    extraAllowRead = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "~/.cargo" ];
      description = "Further sandbox `allowRead` paths for a repo with `readFence` on, such as a `path:` devenv input or a tool's cache under `$HOME`.";
    };

    extraAllowedDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "dev.azure.com" ];
      description = ''
        Project domains, written to the repo file's
        `sandbox.network.allowedDomains`. Whether a managed sandbox honours
        a project entry (merged, ignored or prompted) is open: live check V2
        of the 2026-10-27 redesign, pending. Until it passes, a domain the
        project cannot work without also belongs in the host's list
        (`extraAllowedDomains` in the ai-jailer checkout's host.nix).
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      example = {
        permissions.allow = [ "Bash(terraform plan *)" ];
      };
      description = ''
        Extra project settings merged into the generated .claude/settings.json.
        Lists replace rather than append; use `extraDeny` and
        `extraAllowedDomains` to add to the managed lists.
      '';
    };

    claudeCode.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = "claude-code, tmux and jq in the project shell, for hosts that do not put them on PATH. Needs `allow_unfree: true` in devenv.yaml.";
    };

    managedSettingsPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/claude-code/managed-settings.json";
      description = "Where the host keeps the law (the managed settings); every shell entry warns when it is unreadable.";
    };

  };

  config = lib.mkMerge [
    # Tools, not rules: in the shell whether or not the guard rails are on.
    # `ajmux` in the project shell only; aj bootstrap adds it to the
    # user's profile host-wide.
    {
      packages = [
        ajmux
      ]
      ++ lib.optionals cfg.claudeCode.enable [
        claudeCode
        pkgs.tmux
        pkgs.jq # reason not recorded; aj init gets its own jq (pkgs/aj.nix)
      ];
    }

    (lib.mkIf cfg.enable {
      files.".claude/settings.json".json = lib.recursiveUpdate (jailerLib.projectSettings {
        repoRoot = config.devenv.root;
        inherit (cfg)
          platform
          readFence
          extraAllowRead
          allowConnectors
          extraDeny
          extraAllowedDomains
          ;
      }) cfg.settings;

      enterShell = ''
        [ -r "${cfg.managedSettingsPath}" ] || echo "ai-jail: ${cfg.managedSettingsPath} is missing: no law, jail or hook on this host (aj bootstrap from the ai-jailer checkout's devenv shell)" >&2
        # Name this project for `ajmux`: <org>/<repo> relative to the code
        # root, from the main checkout or any worktree under it, else
        # local/<name> with the directory alongside. A bare `ajmux` in this
        # shell then opens the right tmux session.
        _ai_jail_root="''${AI_JAILER_CODE_ROOT:-$HOME/code/git}"; _ai_jail_root="''${_ai_jail_root%/}"
        if [[ "$DEVENV_ROOT" == "$_ai_jail_root/"*/* ]]; then
          _ai_jail_rel="''${DEVENV_ROOT#"$_ai_jail_root/"}"
          IFS=/ read -r _ai_jail_a _ai_jail_b _ <<<"$_ai_jail_rel"
          export AI_JAIL_PROJECT="$_ai_jail_a/$_ai_jail_b"
          unset _ai_jail_rel _ai_jail_a _ai_jail_b AI_JAIL_PROJECT_DIR
        else
          export AI_JAIL_PROJECT="local/${projectName}"
          export AI_JAIL_PROJECT_DIR="$DEVENV_ROOT"
        fi
        unset _ai_jail_root
      '';
    })

    # Off: no file, so devenv's files cleanup removes the settings link from
    # the last shell entry, and no AI_JAIL_PROJECT, so nothing reads this
    # repo as governed (a bare `ajmux` still resolves it from the cwd under
    # the code root). Said at every entry, never silent.
    (lib.mkIf (!cfg.enable) {
      enterShell = ''
        echo "ai-jail: guard rails off for this repo (ai-jail.enable = false in devenv.nix)" >&2
      '';
    })
  ];
}
