# Links the managed tree at /etc/claude-code, root-owned, so every Claude
# Code session on the host is bound by it, and creates one worker user per
# customer from `harness.workers` (2026-10-27). The same module serves
# NixOS-WSL at work and native NixOS at home.
{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.harness;
  package = import ../lib/managed-tree.nix {
    inherit pkgs lib;
    inherit (cfg)
      platform
      allowLocalCommits
      allowMemoryEdits
      allowConnectors
      extraDeny
      extraAllowedDomains
      allowManagedHooksOnly
      direnvPackage
      extraKnownMarketplaces
      ;
  };
  devenvCache = import ../pkgs/devenv-cache.nix;
  workerUsers = lib.mapAttrsToList (_: w: w.user) cfg.workers;
  hmWorkers = lib.filterAttrs (_: w: w.homeManager) cfg.workers;
  # trusted-users takes `@group` entries too: each worker's primary group
  # (named after it), its extraGroups, and `agents`, which holds every worker.
  untrustable = lib.unique (
    lib.concatMap (w: [ w.user ] ++ map (g: "@${g}") ([ w.user ] ++ w.extraGroups)) (
      lib.attrValues cfg.workers
    )
    ++ lib.optional (cfg.workers != { }) "@agents"
  );
  trustedWorkers = lib.intersectLists untrustable config.nix.settings.trusted-users;
in
{
  options.harness = {
    enable = lib.mkEnableOption "the guard-railed Claude Code managed configuration";

    platform = lib.mkOption {
      type = lib.types.enum [
        "linux"
        "wsl"
      ];
      default = if lib.attrByPath [ "wsl" "enable" ] false config then "wsl" else "linux";
      defaultText = lib.literalExpression ''if config.wsl.enable then "wsl" else "linux"'';
      description = "Host kind. `wsl` adds the Windows-interop mitigations to the sandbox.";
    };

    owner = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "raul";
      description = ''
        The human's login. Member of every worker's primary group, so it can
        read worker homes, and the one account with a sudo rule to the
        workers (`ownerSudo`). Required when `workers` is non-empty.
      '';
    };

    workers = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              user = lib.mkOption {
                type = lib.types.str;
                default = "w-${name}";
                defaultText = lib.literalExpression ''"w-''${name}"'';
                description = "The worker's login. Its primary group has the same name.";
              };
              uid = lib.mkOption {
                type = lib.types.nullOr lib.types.int;
                default = null;
                description = "Fixed UID; null lets NixOS allocate one.";
              };
              gitName = lib.mkOption {
                type = lib.types.str;
                example = "Claude (acme)";
                description = "Git author name in the worker's Home Manager config.";
              };
              gitEmail = lib.mkOption {
                type = lib.types.str;
                example = "claude-acme@example.invalid";
                description = "Git author email in the worker's Home Manager config.";
              };
              extraGroups = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Groups besides `agents`. Never `wheel`: the worker would gain sudo.";
              };
              homeManager = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Give the worker a Home Manager config importing `home/`. Takes effect only where the host imports the Home Manager NixOS module.";
              };
              codeRoot = lib.mkOption {
                type = lib.types.str;
                default = "code/git";
                description = "The worker's clone directory, relative to its home.";
              };
            };
          }
        )
      );
      default = { };
      example = lib.literalExpression ''
        {
          acme = {
            gitName = "Claude (acme)";
            gitEmail = "claude-acme@example.invalid";
          };
        }
      '';
      description = ''
        One Linux user per customer, keyed by customer name: own 0750 home,
        own Claude login, own git identity, lingering on, member of the
        marker group `agents`, never in `nix.settings.trusted-users`.
      '';
    };

    ownerSudo = lib.mkOption {
      type = lib.types.enum [
        "nopasswd"
        "password"
        "none"
      ];
      default = "nopasswd";
      description = "The owner's sudo rule to every `agents` member: without a password, with one, or no rule.";
    };

    devenvCache = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Add devenv.cachix.org (`pkgs/devenv-cache.nix`) to the root nix.conf. Workers are not trusted users, so they cannot add it themselves.";
    };

    extraKnownMarketplaces = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      example = lib.literalExpression ''[ { source = "github"; repo = "anthropics/claude-plugins-official"; } ]'';
      description = ''
        Plugin marketplaces a user may add, written as the managed
        `strictKnownMarketplaces` list. Empty, the default: no marketplace
        can be added at all. The harness ships no mods and registers no
        marketplace of its own. A source here lets the user of a mixed host
        add that marketplace and its plugins (their hooks run only with
        `allowManagedHooksOnly = false`); mods stay refused by the built-in
        guard (`allowManagedModsOnly`) whatever this lists.
      '';
    };

    allowLocalCommits = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Let agents commit on their worktree branch. Push stays impossible either way (decision 7.5 of a design brief not kept in this repo).";
    };

    allowMemoryEdits = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Let agents write their auto-memory under ~/.claude/projects/<slug>/memory/.
        Everything else under ~/.claude stays read-only. Off on a work host:
        memory is a persistent channel into every later session on the
        machine. On for a mixed host where the user wants Claude Code
        to remember things.
      '';
    };

    allowConnectors = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Let the claude.ai account's connectors (Gmail, Drive, Notion, ...)
        load in sessions. They are MCP servers outside the Bash sandbox, so
        off by default; a `false` here holds against every repo and user file.
      '';
    };

    allowManagedHooksOnly = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Only managed and built-in hooks run; user, project and plugin hooks are ignored. Set false where the user relies on plugin hooks.";
    };

    extraDeny = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "Bash(az devops *)" ];
      description = "Additional permission deny rules appended to the managed set.";
    };

    extraAllowedDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "dev.azure.com" ];
      description = "Additional sandbox network allowlist entries.";
    };

    direnvPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.direnv;
      defaultText = lib.literalExpression "pkgs.direnv";
      description = "direnv used by the env hook. Must match the user's direnv so `direnv allow` state is shared.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = package;
      description = "The generated managed tree (managed-settings.json, hooks/).";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = config.security.allowUserNamespaces;
            message = "harness: the Claude Code sandbox (bubblewrap) needs security.allowUserNamespaces = true.";
          }
          {
            assertion = cfg.workers == { } || cfg.owner != null;
            message = "harness: harness.workers is set, so harness.owner must name the human's login.";
          }
          {
            assertion = !(lib.elem cfg.owner workerUsers);
            message = "harness: harness.owner (${toString cfg.owner}) must not be a worker user.";
          }
          {
            assertion = trustedWorkers == [ ];
            message = "harness: worker users and their groups must not be in nix.settings.trusted-users: ${lib.concatStringsSep ", " trustedWorkers}.";
          }
          {
            assertion = lib.all (u: builtins.match "[a-z_][a-z0-9_-]*" u != null) workerUsers;
            message = "harness: worker user names must match ^[a-z_][a-z0-9_-]*$: ${lib.concatStringsSep ", " workerUsers}.";
          }
          {
            assertion = lib.length (lib.unique workerUsers) == lib.length workerUsers;
            message = "harness: worker user names must be distinct: ${lib.concatStringsSep ", " workerUsers}.";
          }
        ];

        # A symlink into the store: root-owned, read-only, replaced atomically on rebuild.
        environment.etc."claude-code".source = package;

        nix.settings = lib.mkIf cfg.devenvCache {
          extra-substituters = [ devenvCache.url ];
          extra-trusted-public-keys = [ devenvCache.key ];
        };
      }

      (lib.mkIf (cfg.workers != { }) {
        users.groups = {
          agents = { };
        }
        // lib.mapAttrs' (
          _: w:
          lib.nameValuePair w.user {
            # The null guards here and on the sudo rule let the owner
            # assertion report a missing owner instead of a type error.
            members = [ w.user ] ++ lib.optional (cfg.owner != null) cfg.owner;
          }
        ) cfg.workers;

        users.users = lib.mapAttrs' (
          name: w:
          lib.nameValuePair w.user (
            {
              isNormalUser = true;
              group = w.user;
              extraGroups = [ "agents" ] ++ w.extraGroups;
              home = "/home/${w.user}";
              homeMode = "0750";
              createHome = true;
              linger = true;
              shell = pkgs.bashInteractive;
              # The GECOS field: no colons, no newlines.
              description = "claude-nix-harness worker for ${name}";
            }
            // lib.optionalAttrs (w.uid != null) { inherit (w) uid; }
          )
        ) cfg.workers;

        # The sudo module splices runAs verbatim into the sudoers Runas list,
        # so "%agents" means any member of the agents group.
        security.sudo.extraRules = lib.optional (cfg.ownerSudo != "none" && cfg.owner != null) {
          users = [ cfg.owner ];
          runAs = "%agents";
          commands = [
            {
              command = "ALL";
              options = lib.optional (cfg.ownerSudo == "nopasswd") "NOPASSWD";
            }
          ];
        };
      })

      # Keyed on the option tree, not on config, so a host without the Home
      # Manager NixOS module still evaluates.
      (lib.optionalAttrs (options ? home-manager) {
        home-manager.users = lib.mapAttrs' (
          _: w:
          lib.nameValuePair w.user {
            imports = [ ../home ];
            harness = {
              enable = true;
              codeRoot = "/home/${w.user}/${w.codeRoot}";
            };
            programs.git = {
              enable = true;
              userName = w.gitName;
              userEmail = w.gitEmail;
            };
            home.stateVersion = config.system.stateVersion;
          }
        ) hmWorkers;
      })
    ]
  );
}
