# One function, two destinations.
#
# `managed = true` is the root-owned /etc/claude-code/managed-settings.json.
# It is host-wide (there is no per-user or per-group managed file) and binds
# every user, the owner and each worker alike: every deny rule, every hook,
# the sandbox with its credential and network lists, and the mod policy.
# Nothing in ~/.claude or in a repo overrides a key set there.
#
# `managed = false` is the repo's .claude/settings.json the devenv module
# writes: the project layer. Allow rules come from `harness.settings`
# (merged by the devenv module), deny rules from `extraDeny`, plus literal
# `denyWrite` paths under the checkout, the project's extra domains, the
# read fence when on, and a few scalars repeated as a belt. It carries no
# hooks, no base deny list and no credential lists: without the managed
# file a repo enforces only what it adds.
#
# Scopes, checked 2026-10-27 against the settings reference: `permissions`
# deny rules, `sandbox.enabled`, `allowUnsandboxedCommands`,
# `filesystem.denyRead`/`denyWrite`, `credentials` and `allowedDomains` are
# honoured from any scope, and deny lists merge across scopes;
# `allowManagedHooksOnly` is managed only; `syncClaudeAiSkills`/`Plugins`
# honour a `false` from user, local or managed scope, never from a project.
# Re-check after upgrades.
{ lib }:
{
  managed ? true,
  # "linux" or "wsl"
  platform,
  # Managed only, required there: where the hooks live
  # (/etc/claude-code/hooks).
  hookDir ? null,
  allowLocalCommits ? false,
  allowMemoryEdits ? false,
  # Let the claude.ai account's connectors (Gmail, Drive, Notion, ...) load.
  # They are MCP servers that run outside the Bash sandbox, so a session with
  # them can move data out of the repo without any command the hook sees.
  allowConnectors ? false,
  extraDeny ? [ ],
  extraAllowedDomains ? [ ],
  allowManagedHooksOnly ? true,
  # Managed only. false writes `syncClaudeAiSkills` and `syncClaudeAiPlugins`
  # as false, so no skill or plugin synced from the claude.ai account loads
  # for any user on the host.
  syncClaudeAi ? false,
  # Managed only. The whole of `strictKnownMarketplaces` (a list of sources
  # the user may add); not the settings key of the same name, which
  # registers marketplaces and is never written. Empty, the default: no
  # marketplace can be added at all.
  extraKnownMarketplaces ? [ ],
  # Repo only, required there: the checkout's absolute path (devenv's
  # `config.devenv.root`). Linux skips glob `denyWrite` entries, so the repo
  # copy lists its own settings, hooks and `.git` files as literal paths. A
  # worktree has a `.git` file, not a directory; its hooks and config live
  # under the main checkout, which that checkout's own file covers.
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
assert lib.assertMsg (
  !managed || hookDir != null
) "lib/settings.nix: hookDir is required when managed";
assert lib.assertMsg (
  managed || repoRoot != null
) "lib/settings.nix: repoRoot is required for the repo settings";
let
  denyRules = import ./deny-rules.nix { inherit lib; };
  sshSandbox = import ./ssh-sandbox.nix;
  envGuard = "${hookDir}/env-guard.sh";
  tmuxNotify = "${hookDir}/tmux-notify.sh";
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
  withFence =
    filesystem:
    filesystem
    // lib.optionalAttrs readFence {
      denyRead = (filesystem.denyRead or [ ]) ++ [ "~/" ];
      allowRead = fenceAllowRead ++ extraAllowRead;
    };
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

  # Both bodies carry these; the repo copy repeats them as a belt.
  common = {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    worktree.baseRef = "head";
    # Honoured from any scope, the repo file included; a `true` in user or
    # managed settings cannot be undone here.
    disableClaudeAiConnectors = !allowConnectors;
    includeCoAuthoredBy = false;
  };
  sandboxScalars = {
    enabled = true;
    # In managed settings a false holds against a repo's true (2.1.285+).
    allowUnsandboxedCommands = false;
    failIfUnavailable = true;
  };

  # `args = []` selects exec form so the path is never re-parsed by `sh -c`.
  hook =
    extra:
    {
      type = "command";
      command = envGuard;
      args = [ ];
    }
    // extra;

  managedBody =
    common
    // {
      permissions = {
        defaultMode = "default";
        # Honoured from any scope; a repo can disable bypass mode, never enable it.
        disableBypassPermissionsMode = "disable";
        deny = denyRules { inherit allowLocalCommits allowMemoryEdits; } ++ extraDeny;
      };

      # No `env.CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` anywhere (2026-10-22): a repo
      # file carrying it is ignored ("project-scoped settings can't set this
      # key"), and with it in user scope Claude Code 2.1.300 stops auto-allowing
      # sandboxed Bash commands, so every command with a variable, every read
      # outside the working directory and every write under ~/.claude prompts,
      # which a -p session cannot answer (changelog). What strips secrets from
      # the shell is the explicit `credentials.envVars` deny list below.

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
        # local_settings outranks the repo file for scalar keys and settings
        # hot-reload, so the hook blocks it. policy_settings changes cannot be
        # blocked; the hook still runs.
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

      sandbox = sandboxScalars // {
        # The GitHub tokens: no push or `gh` write credential inside the
        # sandbox, the layer the hook's text rules lean on.
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
          ++ sshSandbox.credentials.envVars
          ++ lib.optionals (platform == "wsl") [
            {
              name = "WSL_INTEROP";
              mode = "deny";
            }
          ];
        filesystem = withFence {
          # devenv re-fetches the `path:` harness input on every `direnv export`;
          # Nix needs a writable cache for the fetcher lock, else devenv never
          # loads inside the sandbox and every Claude command runs without it.
          allowWrite = [
            "~/.cache/nix"
            "~/.cache/devenv"
          ];
          # .claude/worktrees must stay writable, so the settings files are
          # listed one by one instead of the whole directory.
          # On Linux and WSL2 only a trailing `/**` works in `allowWrite` and
          # `denyWrite`; a leading `**/` covers nothing (sandboxing docs,
          # checked 2026-10-27; the `**/` entries had no effect live,
          # 2026-10-20). They stay for macOS. On Linux the repo file lists the
          # same paths literally under its root, and the hook refuses shell
          # writes to them.
          denyWrite = [
            "~/.claude"
            "~/.config"
            "~/.azure"
            "~/.ssh"
          ]
          ++ map (p: "**/${p}") repoProtected;
          # The worker's own login and tokens. The owner's files are out of
          # reach through the 0750 homes, not through this list.
          denyRead = [
            "~/.claude/.credentials.json"
            "~/.claude.json"
            "~/.azure"
            # GitHub tokens on disk: gh without a keyring, git's store helper.
            "~/.config/gh"
            "~/.git-credentials"
          ]
          ++ sshSandbox.filesystem.denyRead
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
          # Unlisted hosts prompt.
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
      };

      # The mod policy. The harness ships no mods (2026-10-24, docs/sessions.md
      # section 5), so nothing registers a marketplace or enables a plugin
      # (no `extraKnownMarketplaces` key, no `enabledPlugins`, no
      # `prependPlugins`) and every mod is refused. The built-in guard only
      # loads when managed settings exist and reads `allowManagedModsOnly` from
      # here only; with no organisation mod it refuses them all.
      pluginConfigs."cc-plugin-sec-default@builtin".options.allowManagedModsOnly = true;
      disableSideloadFlags = true;
      # Which marketplaces a user may add; an empty list adds none.
      strictKnownMarketplaces = extraKnownMarketplaces;
    }
    // lib.optionalAttrs (!syncClaudeAi) {
      syncClaudeAiSkills = false;
      syncClaudeAiPlugins = false;
    }
    // lib.optionalAttrs allowManagedHooksOnly { inherit allowManagedHooksOnly; };

  repoBody = common // {
    permissions = {
      disableBypassPermissionsMode = "disable";
      deny = extraDeny;
    };
    sandbox = sandboxScalars // {
      filesystem = withFence {
        # Not devenv.local.*: a literal entry is masked as an unreadable device
        # node whether or not the file exists, and devenv reads both files
        # when they exist, so listing them stopped every shell evaluation
        # inside the sandbox (`harness check` case 2, 2026-10-22). The hook
        # still refuses shell writes to them by name.
        denyWrite = map (p: "${repoRoot}/${p}") (
          lib.filter (p: !lib.hasPrefix "devenv.local." p) repoProtected
        );
      };
      network.allowedDomains = extraAllowedDomains;
    };
  };
in
if managed then managedBody else repoBody
