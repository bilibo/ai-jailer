# Every repo under the harness imports this from devenv.yaml:
#
#   inputs:
#     harness:
#       url: git+https://...  (or path:..., flake: false)
#   imports:
#     - harness/devenv
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
in
{
  options.harness = {
    allowLocalCommits = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Let agents commit on their worktree branch (push stays impossible). Match the host's harness.allowLocalCommits.";
    };

    allowMemoryEdits = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Let agents write their auto-memory under ~/.claude/projects. Match the host's harness.allowMemoryEdits.";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      example = {
        permissions.allow = [ "Bash(terraform plan *)" ];
      };
      description = "Extra project settings merged into the generated .claude/settings.json.";
    };

    managedSettingsPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/claude-code/managed-settings.json";
      description = "Where the host keeps the managed settings; checked at shell entry.";
    };

    container = {
      enable = lib.mkEnableOption "a per-project container image with the managed tree baked in";
      platform = lib.mkOption {
        type = lib.types.enum [
          "linux"
          "wsl"
        ];
        default = "linux";
        description = "Host kind the container runs on.";
      };
      name = lib.mkOption {
        type = lib.types.str;
        default = "claude-harness-${projectName}";
        defaultText = lib.literalExpression ''"claude-harness-''${config.name}"'';
        description = "Image name for `devenv container build harness`.";
      };
    };
  };

  config = lib.mkMerge [
    {
      files.".claude/settings.json".json = lib.recursiveUpdate (harnessLib.projectSettings {
        inherit (cfg) allowLocalCommits allowMemoryEdits;
      }) cfg.settings;

      enterShell = ''
        if [ ! -r "${cfg.managedSettingsPath}" ]; then
          echo "harness: ${cfg.managedSettingsPath} is missing: no hook, no sandbox, no mod policy on this host" >&2
        fi
        # Name this project for `ccode`: <customer>/<repo> relative to the code
        # root, from the main checkout or any worktree under it. A bare `ccode`
        # in this shell then opens the right tmux session.
        _harness_root="''${HARNESS_CODE_ROOT:-$HOME/code/git}"; _harness_root="''${_harness_root%/}"
        if [[ "$DEVENV_ROOT" == "$_harness_root/"*/* ]]; then
          _harness_rel="''${DEVENV_ROOT#"$_harness_root/"}"
          IFS=/ read -r _harness_a _harness_b _ <<<"$_harness_rel"
          export HARNESS_PROJECT="$_harness_a/$_harness_b"
          unset _harness_rel _harness_a _harness_b
        fi
        unset _harness_root
      '';
    }

    (lib.mkIf cfg.container.enable {
      packages = [
        pkgs.claude-code
        pkgs.jq
        pkgs.tmux
        pkgs.git
      ];
      containers.harness = {
        name = cfg.container.name;
        copyToRoot = pkgs.runCommand "claude-harness-root" { } ''
          mkdir -p $out/etc
          ln -s ${
            import ../lib/managed-tree.nix {
              inherit pkgs lib;
              inherit (cfg) allowLocalCommits;
              inherit (cfg.container) platform;
            }
          } $out/etc/claude-code
        '';
        startupCommand = "bash -l";
      };
    })
  ];
}
