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

  seedFile = pkgs.writeText "claude-settings-seed.json" (builtins.toJSON cfg.userSettingsSeed);
in
{
  options.harness = {
    enable = lib.mkEnableOption "the user side of the guard-railed Claude Code setup";

    codeRoot = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/code/git";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/code/git"'';
      description = "Directory holding <customer>/<repo> checkouts; `ccmux` resolves project names under it.";
    };

    userSettingsSeed = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      example = {
        model = "sonnet";
      };
      description = ''
        Keys written into `~/.claude/settings.json` once, at activation, when
        that file does not exist; an existing file is never touched. Claude
        Code owns the file afterwards (`/model` writes it), so it is a 0600
        copy, never a store symlink. Not a place for rules: deny rules, hooks
        and the sandbox come from the managed settings.
      '';
    };

    direnvPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.direnv;
      defaultText = lib.literalExpression "pkgs.direnv";
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
    # Every harness .envrc calls `require_allowed` (direnv >= 2.38). nixpkgs
    # ships 2.38.2 since this flake's 2026-10-23 lock; before that
    # pkgs/direnv.nix built it, so an older nixpkgs now fails here instead.
    assertions = [
      {
        assertion = lib.versionAtLeast cfg.direnvPackage.version "2.38";
        message = "harness.direnvPackage is direnv ${cfg.direnvPackage.version}; `require_allowed` needs 2.38 or newer (update nixpkgs).";
      }
    ];

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
        # Shared with harness bootstrap, so a bootstrapped host gets the same settings.
        config.global = (builtins.fromTOML (builtins.readFile ../pkgs/direnv.toml)).global;
      };

      tmux = {
        enable = true;
        extraConfig = builtins.readFile ../pkgs/tmux.conf;
      };
    };

    home = {
      packages = [
        # Every repo's .envrc runs `devenv direnvrc`.
        pkgs.devenv
        pkgs.jq
        ccmux
      ];

      sessionVariables = {
        # `ccmux` and the devenv module's HARNESS_PROJECT export agree on the root.
        HARNESS_CODE_ROOT = cfg.codeRoot;
      };

      # Runs even with the empty default seed, writing `{}`: whether Claude
      # Code needs the file to exist at all is live check V6 (2026-10-27,
      # pending), which decides if an empty seed can be skipped. After
      # linkGeneration, which removes the links the new generation dropped,
      # so the store symlink an older generation of this module wrote here
      # (changelog 2026-10-24) is gone first; a symlink still in place is
      # left alone rather than written through. `run` makes
      # `home-manager switch --dry-run` print the commands instead.
      activation.harnessSeedClaudeSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        if [ ! -e "$HOME/.claude/settings.json" ] && [ ! -L "$HOME/.claude/settings.json" ]; then
          run mkdir -p "$HOME/.claude"
          run install -m 0600 ${seedFile} "$HOME/.claude/settings.json"
        fi
      '';
    };
  };
}
