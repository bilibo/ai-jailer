# One settings body, two destinations. `managed = true` is the root-owned
# /etc/claude-code/managed-settings.json: nothing in ~/.claude or in a repo
# can override a key set there. `managed = false` is the repo's
# .claude/settings.json the devenv module writes: the same rules, minus the
# keys Claude Code reads from managed settings only, so a host without
# managed settings (a personal laptop) still gets deny rules, every hook and
# the sandbox from the repo alone. On a managed host the two agree;
# `allowManagedHooksOnly` (the work-host default) keeps the repo copy of the
# hooks from running as well. A mixed host that sets it false runs both
# copies on every event: same verdicts, and the env preamble is written
# twice with identical content.
#
# Key names and scopes checked against the Claude Code settings reference on
# 2026-10-18 for version 2.1.296. Re-check after upgrades.
{ lib }:
{
  managed ? true,
  # "linux" or "wsl"
  platform,
  # Where the hooks live: /etc/claude-code/hooks (stable) or the store path
  # of lib/hooks.nix (the repo settings are regenerated at every shell entry).
  hookDir,
  # Managed only.
  marketplaceDir ? null,
  allowLocalCommits ? false,
  allowMemoryEdits ? false,
  # Managed only. Non-empty: managed deny rules carry only the universal
  # subset, the hook applies project rules by cwd, the repo carries the
  # full set.
  enforcementRoots ? [ ],
  extraDeny ? [ ],
  extraAllowedDomains ? [ ],
  allowManagedHooksOnly ? true,
  # Managed only (user-or-managed scope; a repo cannot set it).
  # true: unknown hosts are refused inside the sandbox; false: prompted.
  strictAllowlist ? true,
  # Managed only. Same shape as strictKnownMarketplaces.
  extraKnownMarketplaces ? [ ],
}:
let
  denyRules = import ./deny-rules.nix { inherit lib; };
  # A project rule: in the managed copy only when the host enforces
  # everywhere, in the repo copy always (see ssh-sandbox.nix).
  sshSandbox = import ./ssh-sandbox.nix;
  everywhere = !managed || enforcementRoots == [ ];
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
assert managed -> marketplaceDir != null;
{
  "$schema" = "https://json.schemastore.org/claude-code-settings.json";

  permissions = {
    defaultMode = "default";
    # Honoured from any scope; a repo can disable bypass mode, never enable it.
    disableBypassPermissionsMode = "disable";
    deny =
      denyRules {
        inherit allowLocalCommits allowMemoryEdits;
        scope = if everywhere then "all" else "universal";
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
    # local_settings outranks the repo file for scalar keys (sandbox.enabled,
    # defaultMode) and settings hot-reload, so the hook blocks it under the
    # roots. policy_settings changes cannot be blocked; the hook still runs.
    ConfigChange = [
      {
        matcher = "user_settings|policy_settings|local_settings";
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
    # A false here holds against a repo's true (2.1.285+); the repo copy
    # repeats it so a host without managed settings gets the same.
    allowUnsandboxedCommands = false;
    failIfUnavailable = true;
    filesystem = {
      # devenv re-fetches the `path:` harness input on every `direnv export`;
      # Nix needs a writable cache for the fetcher lock, else devenv never
      # loads inside the sandbox and every Claude command runs without it.
      allowWrite = [
        "~/.cache/nix"
        "~/.cache/devenv"
      ];
      # Deny entries merge across scopes; no lower scope removes one.
      # .claude/worktrees must stay writable, so the settings files are
      # listed one by one instead of the whole directory.
      denyWrite = [
        "~/.claude"
        "~/.config"
        "~/.azure"
        "~/.ssh"
        "**/.git/hooks"
        "**/.git/config"
        "**/.claude/settings.json"
        "**/.claude/settings.local.json"
        "**/.claude/hooks"
        "**/.claude/skills"
        "**/.claude-plugin"
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
    }
    // lib.optionalAttrs managed { inherit strictAllowlist; };
    # `deny` entries survive in a repo file; only `mask` entries are dropped
    # from project and local scope.
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
}
// lib.optionalAttrs managed {
  # The built-in guard only loads when managed settings exist and reads
  # `allowManagedModsOnly` from here only. The managed marketplace is empty
  # until the broker mod exists, so the guard refuses every mod.
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
// lib.optionalAttrs (managed && allowManagedHooksOnly) { allowManagedHooksOnly = true; }
