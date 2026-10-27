# Every repo under the harness imports this from devenv.yaml:
#
#   inputs:
#     harness:
#       url: github:bilibo/claude-nix-harness  (or path:..., flake: false)
#   imports:
#     - harness/devenv
#
# It writes the repo's .claude/settings.json, the project layer
# (`projectSettings` in lib/settings.nix): the allow rules from `settings`,
# the deny rules from `extraDeny`, the project's domains, the read fence
# when on, literal `denyWrite` entries for the repo's own settings, hooks
# and git files under the checkout, and a few scalars repeated as a belt.
# The deny rules, the hooks and the sandbox with its credential and network
# lists come from the host's managed settings (`managedSettingsPath`); on a
# host without that file the repo has none of them, and every shell entry
# says so.
#
# `harness.enable = false` is the repo owner's off switch: no settings file
# (devenv's files cleanup removes the link it wrote before), so none of the
# project layer, and no HARNESS_* exports; a notice at every shell entry
# says so. The packages stay: they are tools, not rules. A session cannot
# set it where the managed settings are in place: their deny rules and hook
# refuse its edits to devenv.nix, the same as for every other option here.
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
  cfg = config.harness;
  harnessLib = import ../lib { inherit lib; };
  projectName = if config.name == null then "project" else config.name;

  ccmux = import ../pkgs/ccmux.nix { inherit pkgs; };
  # nixpkgs' claude-code without the LD_LIBRARY_PATH its wrapper leaks into
  # every command (pkgs/claude-code.nix).
  claudeCode = import ../pkgs/claude-code.nix { inherit pkgs; };
in
{
  options.harness = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        The project layer for this repo. `false` turns it off: no
        .claude/settings.json (devenv removes the one it wrote before), so
        none of the repo's allow rules, extra deny rules, domains or read
        fence, no HARNESS_* exports, and a one-line notice at shell entry.
        The packages (ccmux, claudeCode.enable's) stay. The host's managed
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
        (`extraAllowedDomains` in the harness checkout's host.nix).
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
        `extraAllowedDomains` to add to the harness lists.
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
      description = "Where the host keeps the managed settings; every shell entry warns when it is unreadable.";
    };

  };

  config = lib.mkMerge [
    # Tools, not rules: in the shell whether or not the guard rails are on.
    # `ccmux` in the project shell only; harness bootstrap adds it to the
    # user's profile host-wide.
    {
      packages = [
        ccmux
      ]
      ++ lib.optionals cfg.claudeCode.enable [
        claudeCode
        pkgs.tmux
        pkgs.jq # reason not recorded; harness init gets its own jq (pkgs/harness.nix)
      ];
    }

    (lib.mkIf cfg.enable {
      files.".claude/settings.json".json = lib.recursiveUpdate (harnessLib.projectSettings {
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
        [ -r "${cfg.managedSettingsPath}" ] || echo "harness: ${cfg.managedSettingsPath} is missing: no deny rules, hook or sandbox on this host (harness bootstrap from the harness checkout's devenv shell)" >&2
        # Name this project for `ccmux`: <customer>/<repo> relative to the code
        # root, from the main checkout or any worktree under it, else
        # local/<name> with the directory alongside. A bare `ccmux` in this
        # shell then opens the right tmux session.
        _harness_root="''${HARNESS_CODE_ROOT:-$HOME/code/git}"; _harness_root="''${_harness_root%/}"
        if [[ "$DEVENV_ROOT" == "$_harness_root/"*/* ]]; then
          _harness_rel="''${DEVENV_ROOT#"$_harness_root/"}"
          IFS=/ read -r _harness_a _harness_b _ <<<"$_harness_rel"
          export HARNESS_PROJECT="$_harness_a/$_harness_b"
          unset _harness_rel _harness_a _harness_b HARNESS_PROJECT_DIR
        else
          export HARNESS_PROJECT="local/${projectName}"
          export HARNESS_PROJECT_DIR="$DEVENV_ROOT"
        fi
        unset _harness_root
      '';
    })

    # Off: no file, so devenv's files cleanup removes the settings link from
    # the last shell entry, and no HARNESS_PROJECT, so nothing reads this
    # repo as governed (a bare `ccmux` still resolves it from the cwd under
    # the code root). Said at every entry, never silent.
    (lib.mkIf (!cfg.enable) {
      enterShell = ''
        echo "harness: guard rails off for this repo (harness.enable = false in devenv.nix)" >&2
      '';
    })
  ];
}
