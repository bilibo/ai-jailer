# home-manager module: the user side of the harness. Platform-neutral.
#
# - programs.claude-code with the worktree setting (deny rules and hooks
#   come from managed settings, never from here)
# - direnv with nix-direnv and a strict direnv.toml, no whitelist entries
# - tmux: never let panes inherit another project's direnv variables, and
#   pass Claude Code's key chords through
# - `ccode <customer>/<repo> [claude args]`: tmux session per project
#
# Nothing here for SSH on purpose: a passphrase key must never sit in an
# agent, so there is no agent to configure (README, "Git over SSH").
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.harness;

  ccode = import ../pkgs/ccode.nix {
    inherit pkgs;
    codeRoot = cfg.codeRoot;
  };
in
{
  options.harness = {
    enable = lib.mkEnableOption "the user side of the guard-railed Claude Code setup";

    codeRoot = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/code/git";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/code/git"'';
      description = "Directory holding <customer>/<repo> checkouts; `ccode` resolves project names under it. Usually one of the NixOS module's enforcementRoots.";
    };

    direnvPackage = lib.mkOption {
      type = lib.types.package;
      default =
        if lib.versionOlder pkgs.direnv.version "2.38" then
          import ../pkgs/direnv.nix { inherit pkgs; }
        else
          pkgs.direnv;
      defaultText = lib.literalExpression "pkgs.direnv (>= 2.38)";
      description = "direnv >= 2.38 for `require_allowed` in .envrc files.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.claude-code = {
      enable = true;
      settings.worktree.baseRef = "head";
    };

    programs.direnv = {
      enable = true;
      package = cfg.direnvPackage;
      nix-direnv.enable = true;
      config.global = {
        # Start every .envrc from a clean, predictable environment.
        strict_env = true;
        # devenv evaluations are slow; the default 5s warning is noise.
        warn_timeout = "2m";
        # Never read .env files implicitly (credentials).
        load_dotenv = false;
        # No whitelist.prefix entries, ever: path-only, never re-prompts.
      };
    };

    programs.tmux = {
      enable = true;
      extraConfig = ''
        # --- claude-harness ---
        # The tmux server keeps the first client's environment. Refresh these
        # on attach and never seed them into new panes, so a pane opened from
        # customer A's shell never carries A's direnv state into customer B.
        set -ga update-environment "DIRENV_DIR DIRENV_DIFF DIRENV_WATCHES DIRENV_FILE"
        set-environment -gu DIRENV_DIR
        set-environment -gu DIRENV_DIFF
        set-environment -gu DIRENV_WATCHES
        set-environment -gu DIRENV_FILE
        # Claude Code's TUI: shift+enter and other chords need extended keys,
        # focus events keep its redraws right, passthrough lets it talk to the
        # outer terminal (clipboard, images).
        set -g extended-keys on
        set -g focus-events on
        set -g allow-passthrough on
      '';
    };

    home.packages = [
      # .envrc runs `devenv direnvrc`; the hook runs `direnv export` per command.
      pkgs.devenv
      pkgs.jq
      ccode
    ];

    # `ccode` and the devenv module's HARNESS_PROJECT export agree on the root.
    home.sessionVariables.HARNESS_CODE_ROOT = cfg.codeRoot;
  };
}
