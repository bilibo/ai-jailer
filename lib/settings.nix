# One settings body, two destinations. `managed = true` is the root-owned
# /etc/claude-code/managed-settings.json: nothing in ~/.claude or in a repo
# can override a key set there. `managed = false` is the repo's
# .claude/settings.json the devenv module writes: the same rules, minus the
# keys Claude Code reads from managed settings only, so a host without
# managed settings (an unmanaged host) still gets deny rules, every hook and
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
  # Let the claude.ai account's connectors (Gmail, Drive, Notion, ...) load.
  # They are MCP servers that run outside the Bash sandbox, so a session with
  # them can move data out of the repo without any command the hook sees.
  allowConnectors ? false,
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
  # Managed only. Same shape as strictKnownMarketplaces (a list of sources
  # the user may add); not the settings key of the same name, which
  # registers marketplaces and is written below from `mods`.
  extraKnownMarketplaces ? [ ],
  # Managed only. Names of the mods in the managed marketplace directory
  # (lib/mods.nix). Non-empty: the directory is registered by absolute path
  # and each mod enabled from it, which is what makes them the
  # organisation's mods under the guard (docs/sessions.md section 5).
  mods ? [ ],
  marketplaceName ? "harness",
  # Repo only: the checkout's absolute path (devenv's `config.devenv.root`).
  # Linux skips glob `denyWrite` entries, so the repo copy also lists its own
  # settings, hooks and `.git` files as literal paths. A worktree has a
  # `.git` file, not a directory; its hooks and config live under the main
  # checkout, which that checkout's own file covers.
  repoRoot ? null,
  # Read fence: `denyRead ["~/"]` with `allowRead` for the repo and the paths
  # the devenv shell entry needs (the narrower path wins). Everything else
  # under $HOME, sibling repos included, is unreadable inside the sandbox.
  # Off by default until the live cases pass (roadmap, sandbox hardening).
  readFence ? false,
  # Further `allowRead` entries for a fenced repo: a `path:` devenv input,
  # `~/.cargo` for a Rust project, ...
  extraAllowRead ? [ ],
}:
let
  denyRules = import ./deny-rules.nix { inherit lib; };
  # A project rule: in the managed copy only when the host enforces
  # everywhere, in the repo copy always (see ssh-sandbox.nix).
  sshSandbox = import ./ssh-sandbox.nix;
  everywhere = !managed || enforcementRoots == [ ];
  envGuard = "${hookDir}/env-guard.sh";
  # What a sandboxed command reads under $HOME when the fence is on, from an
  # strace of `direnv export` in the test repo (2026-10-21): the Nix profile
  # and its state, the direnv config and allow database, the Nix and devenv
  # caches and devenv's GC roots, the shell snapshot Claude Code's Bash tool
  # sources (the credentials file next to it stays hidden), git's global
  # config.
  fenceAllowRead = [
    (if repoRoot != null then repoRoot else ".")
    "~/.nix-profile"
    "~/.local/state/nix"
    "~/.cache/nix"
    "~/.cache/devenv"
    "~/.local/share/devenv"
    "~/.local/share/direnv"
    "~/.config/direnv"
    "~/.claude/shell-snapshots"
    "~/.gitconfig"
  ];
  # Paths under a checkout that no shell command may write: the agent's own
  # rules, its hooks and skills, git's exec vectors, and devenv's
  # auto-imported local files, which no direnv re-approval covers. A path
  # that does not exist is masked, so it cannot be created either.
  repoProtected = [
    ".git/hooks"
    ".git/config"
    "devenv.local.nix"
    "devenv.local.yaml"
    ".claude/settings.json"
    ".claude/settings.local.json"
    ".claude/hooks"
    ".claude/skills"
    ".claude-plugin"
  ];
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

  # Honoured from any scope, the repo file included; a `true` in user or
  # managed settings cannot be undone here. Account-synced skills and plugins
  # (`syncClaudeAiSkills`, `syncClaudeAiPlugins`) are user-or-managed scope
  # and still load: README, "What a repo cannot enforce on its own".
  disableClaudeAiConnectors = !allowConnectors;

  includeCoAuthoredBy = false;

  # Any scope (project and local after the folder is trusted). Strips
  # credential-shaped variables (by name or value) from every subprocess:
  # Bash commands, hooks, stdio MCP servers; the session keeps its own API
  # credentials. Also pins filesystem isolation on and, on Linux, runs Bash
  # in its own PID namespace. GitHub tokens are kept by the scrub on purpose
  # (gh needs them), hence the explicit `deny` entries below.
  env.CLAUDE_CODE_SUBPROCESS_ENV_SCRUB = "1";

  hooks = {
    # One env hook only: all matching hooks run in parallel and would race on
    # CLAUDE_ENV_FILE.
    SessionStart = [ { hooks = [ (hook { timeout = 30; }) ]; } ];
    CwdChanged = [ { hooks = [ (hook { timeout = 30; }) ]; } ];
    FileChanged = [
      {
        matcher = ".envrc|devenv.nix|devenv.yaml|devenv.lock|devenv.local.nix|devenv.local.yaml";
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
      # On Linux and WSL the `**/` entries have no effect: the sandboxing
      # docs say write entries containing `*`, `?` or `[` are skipped there
      # (confirmed live 2026-10-20). They stay for macOS; under the working
      # directory Claude Code's own protections cover the same files, and the
      # hook refuses shell writes to them. The repo copy adds the same
      # entries as literal paths under `repoRoot`, which Linux honours.
      denyWrite = [
        "~/.claude"
        "~/.config"
        "~/.azure"
        "~/.ssh"
      ]
      ++ map (p: "**/${p}") repoProtected
      ++ lib.optionals (repoRoot != null) (map (p: "${repoRoot}/${p}") repoProtected);
      denyRead = [
        "~/.azure"
        "~/.gnupg"
        "~/.terraform.d"
        "~/.netrc"
      ]
      ++ lib.optionals readFence [ "~/" ]
      ++ lib.optionals everywhere sshSandbox.filesystem.denyRead
      # WSL interop: a denied directory becomes an empty tmpfs, so the
      # interop socket and the Windows drives disappear for sandboxed commands.
      ++ lib.optionals (platform == "wsl") [
        "/run/WSL"
        "/mnt/c"
      ];
    }
    // lib.optionalAttrs readFence { allowRead = fenceAllowRead ++ extraAllowRead; };
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
    # from project and local scope. The GitHub tokens: no push or `gh` write
    # credential inside the sandbox, the layer the hook's text rules lean on.
    credentials.envVars =
      map
        (name: {
          inherit name;
          mode = "deny";
        })
        [
          "ARM_CLIENT_SECRET"
          "AZURE_CLIENT_SECRET"
          "GITHUB_TOKEN"
          "GH_TOKEN"
          "GH_ENTERPRISE_TOKEN"
          "GITHUB_ENTERPRISE_TOKEN"
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
  # `allowManagedModsOnly` from here only. With no mods listed the managed
  # marketplace is empty and unregistered, so the guard refuses every mod.
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
// lib.optionalAttrs (managed && mods != [ ]) {
  # Key shapes from the plugin marketplace, org and mods admin pages
  # (2026-10-21): an object keyed by marketplace name, a `directory` source
  # by absolute path; `enabledPlugins` keyed `<plugin>@<marketplace>`. No
  # `prependPlugins`: once set it must name `sec-default@builtin` or the
  # guard stops loading, and one managed mod needs no ordering.
  extraKnownMarketplaces.${marketplaceName}.source = {
    source = "directory";
    path = marketplaceDir;
  };
  enabledPlugins = lib.listToAttrs (
    map (name: lib.nameValuePair "${name}@${marketplaceName}" true) mods
  );
}
// lib.optionalAttrs (managed && allowManagedHooksOnly) { allowManagedHooksOnly = true; }
