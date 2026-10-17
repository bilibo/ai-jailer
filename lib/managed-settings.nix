# Builds the attrset that becomes /etc/claude-code/managed-settings.json.
#
# Managed settings are the top layer: nothing in ~/.claude or in a repo can
# override a key set here. Every hook lives here (not in user or project
# scope) so a user-tier mod can never override its block and so
# `allowManagedHooksOnly` costs nothing.
#
# Key names checked against the Claude Code settings reference on
# 2026-10-17 for version 2.1.296. Re-check after upgrades.
{ lib }:
{
  # "linux" or "wsl". WSL adds the interop mitigations (see sandbox block).
  platform,
  # Directory holding env-guard.sh and tmux-notify.sh; a stable path, not a
  # store path, so the JSON does not change on every rebuild.
  hookDir,
  # Root-owned marketplace directory for the (future) managed broker mod.
  marketplaceDir,
  allowLocalCommits ? false,
  # Let the agent write its auto-memory (see deny-rules.nix).
  allowMemoryEdits ? false,
  # Directories under which the project rules apply (see deny-rules.nix).
  # Non-empty: managed deny rules carry only the universal subset, the hook
  # applies project rules by cwd, the repo template carries the full set.
  enforcementRoots ? [ ],
  extraDeny ? [ ],
  extraAllowedDomains ? [ ],
  allowManagedHooksOnly ? true,
  # true: unknown hosts are refused inside the sandbox; false: prompted.
  # Strict on a work host, prompt on a personal machine.
  strictAllowlist ? true,
  # Marketplaces allowed besides the managed one, e.g. the user's own plugin
  # sources on a personal machine. Same shape as strictKnownMarketplaces.
  extraKnownMarketplaces ? [ ],
}:
let
  denyRules = import ./deny-rules.nix { inherit lib; };
  # The SSH rule is a project rule: here only when the host enforces
  # everywhere, else from the repo template (see ssh-sandbox.nix).
  sshSandbox = import ./ssh-sandbox.nix;
  everywhere = enforcementRoots == [ ];
  envGuard = "${hookDir}/env-guard.sh";
  tmuxNotify = "${hookDir}/tmux-notify.sh";

  # `args = []` selects exec form so the path is never re-parsed by `sh -c`.
  hook =
    extra:
    {
      type = "command";
      command = envGuard;
      args = [ ];
    }
    // extra;
in
{
  "$schema" = "https://json.schemastore.org/claude-code-settings.json";

  permissions = {
    defaultMode = "default";
    disableBypassPermissionsMode = "disable";
    deny =
      denyRules {
        inherit allowLocalCommits allowMemoryEdits;
        scope = if enforcementRoots == [ ] then "all" else "universal";
      }
      ++ extraDeny;
  };

  worktree.baseRef = "head";

  hooks = {
    # One env hook only: all matching hooks run in parallel and would race on
    # CLAUDE_ENV_FILE.
    SessionStart = [ { hooks = [ (hook { timeout = 30; }) ]; } ];
    CwdChanged = [ { hooks = [ (hook { timeout = 30; }) ]; } ];
    FileChanged = [
      {
        matcher = ".envrc|devenv.nix|devenv.yaml|devenv.lock";
        hooks = [ (hook { timeout = 30; }) ];
      }
    ];
    ConfigChange = [
      {
        matcher = "user_settings|policy_settings";
        hooks = [ (hook { onFailure = "block"; }) ];
      }
    ];
    # onFailure = "block" (2.1.295+): a crashing guard denies instead of
    # failing open.
    PreToolUse = [
      {
        matcher = "Bash|Edit|Write|NotebookEdit";
        hooks = [
          (hook {
            timeout = 10;
            onFailure = "block";
          })
        ];
      }
    ];
    # "Session waits on me" signal for tmux: colour the window, no server.
    Notification = [
      {
        matcher = "permission_prompt|idle_prompt|elicitation_dialog";
        hooks = [
          {
            type = "command";
            command = tmuxNotify;
            args = [ "waiting" ];
            timeout = 5;
          }
        ];
      }
    ];
    UserPromptSubmit = [
      {
        hooks = [
          {
            type = "command";
            command = tmuxNotify;
            args = [ "clear" ];
            timeout = 5;
          }
        ];
      }
    ];
  };

  sandbox = {
    enabled = true;
    # Never let a blocked command re-run outside the sandbox.
    allowUnsandboxedCommands = false;
    # No bubblewrap, no session (not a silent fallback).
    failIfUnavailable = true;
    filesystem = {
      # devenv re-fetches the `path:` harness input on every `direnv export`;
      # Nix needs a writable cache for the fetcher lock, else devenv never
      # loads inside the sandbox and every Claude command runs without it.
      allowWrite = [
        "~/.cache/nix"
        "~/.cache/devenv"
      ];
      denyWrite = [
        "~/.claude"
        "~/.config"
        "~/.azure"
        "~/.ssh"
        "**/.git/hooks"
        "**/.git/config"
        "**/.claude/skills"
      ];
      denyRead = [
        "~/.azure"
        "~/.gnupg"
        "~/.terraform.d"
        "~/.netrc"
      ]
      ++ lib.optionals everywhere sshSandbox.filesystem.denyRead
      # WSL interop: a denied directory becomes an empty tmpfs, so the
      # interop socket and the Windows drives disappear for sandboxed commands.
      ++ lib.optionals (platform == "wsl") [
        "/run/WSL"
        "/mnt/c"
      ];
    };
    network = {
      # go-plugin (terraform, tflint) and the Nix daemon need AF_UNIX, so the
      # seccomp socket filter cannot be used with this stack.
      allowAllUnixSockets = true;
      inherit strictAllowlist;
      allowedDomains = [
        # az / azurerm
        "login.microsoftonline.com"
        "management.azure.com"
        "graph.microsoft.com"
        "*.blob.core.windows.net"
        # terraform providers
        "registry.terraform.io"
        "releases.hashicorp.com"
        # alz provider, ALZ library, tflint rulesets
        "github.com"
        "api.github.com"
        "release-assets.githubusercontent.com"
        "objects.githubusercontent.com"
        # trivy DB
        "ghcr.io"
        "mirror.gcr.io"
        "pkg-containers.githubusercontent.com"
      ]
      ++ extraAllowedDomains;
    };
    credentials.envVars = [
      {
        name = "ARM_CLIENT_SECRET";
        mode = "deny";
      }
      {
        name = "AZURE_CLIENT_SECRET";
        mode = "deny";
      }
    ]
    ++ lib.optionals everywhere sshSandbox.credentials.envVars
    ++ lib.optionals (platform == "wsl") [
      {
        name = "WSL_INTEROP";
        mode = "deny";
      }
    ];
  };

  # Mod policy. The built-in guard only loads when managed settings exist and
  # reads `allowManagedModsOnly` from here only. Until the broker mod exists
  # no marketplace entries are added: the guard then refuses every mod.
  pluginConfigs."cc-plugin-sec-default@builtin".options.allowManagedModsOnly = true;
  disableSideloadFlags = true;
  strictKnownMarketplaces = [
    {
      source = "directory";
      path = marketplaceDir;
    }
  ]
  ++ extraKnownMarketplaces;
}
// lib.optionalAttrs allowManagedHooksOnly { allowManagedHooksOnly = true; }
