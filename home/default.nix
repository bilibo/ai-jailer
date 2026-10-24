# The user side. Deny rules and hooks come from managed settings, never
# from here. Nothing here for SSH on purpose: a passphrase key must never
# sit in an agent, so there is no agent to configure (README, "Git over SSH").
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.harness;

  ccmux = import ../pkgs/ccmux.nix {
    inherit pkgs;
    inherit (cfg) codeRoot;
  };
in
{
  options.harness = {
    enable = lib.mkEnableOption "the user side of the guard-railed Claude Code setup";

    codeRoot = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/code/git";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/code/git"'';
      description = "Directory holding <customer>/<repo> checkouts; `ccmux` resolves project names under it. Usually one of the NixOS module's enforcementRoots.";
    };

    direnvPackage = lib.mkOption {
      type = lib.types.package;
      default = import ../pkgs/direnv.nix { inherit pkgs; };
      defaultText = lib.literalExpression "pkgs.direnv (>= 2.38, overridden while nixpkgs is older)";
      description = "direnv >= 2.38 for `require_allowed` in .envrc files.";
    };

    claudeCodePackage = lib.mkOption {
      type = lib.types.package;
      default = import ../pkgs/claude-code.nix { inherit pkgs; };
      defaultText = lib.literalExpression "pkgs.claude-code without LD_LIBRARY_PATH in its wrapper (pkgs/claude-code.nix)";
      description = "The Claude Code package. The default carries alsa-lib as a RUNPATH instead of the LD_LIBRARY_PATH nixpkgs' wrapper exports into every hook, command and MCP server.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs = {
      # The package only, no `settings`: with any key there home-manager
      # writes `~/.claude/settings.json` as a store symlink, and Claude Code
      # writes that file itself (`/model` at user scope), which then fails
      # with EROFS (changelog 2026-10-24). The one key this carried,
      # `worktree.baseRef`, is in the managed settings and the repo file
      # (lib/settings.nix); on a managed host the user file has nothing to
      # hold that a session could use, and the sandbox denies writing it.
      claude-code = {
        enable = true;
        package = cfg.claudeCodePackage;
      };

      direnv = {
        enable = true;
        package = cfg.direnvPackage;
        nix-direnv.enable = true;
        # Shared with install.sh, so a bootstrapped host gets the same settings.
        config.global = (builtins.fromTOML (builtins.readFile ../pkgs/direnv.toml)).global;
      };

      tmux = {
        enable = true;
        extraConfig = builtins.readFile ../pkgs/tmux.conf;
      };
    };

    home.packages = [
      # Every repo's .envrc runs `devenv direnvrc`.
      pkgs.devenv
      pkgs.jq
      ccmux
    ];

    home.sessionVariables = {
      # `ccmux` and the devenv module's HARNESS_PROJECT export agree on the root.
      HARNESS_CODE_ROOT = cfg.codeRoot;
      # This module goes with the NixOS module; the devenv module warns at
      # shell entry when it sees this but no /etc/claude-code.
      HARNESS_EXPECT_MANAGED = "1";
    };
  };
}
