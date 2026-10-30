# One function, three destinations (roadmap item 14, 2026-10-28).
#
# `body = "law"` is the root-owned /etc/claude-code/managed-settings.json.
# It is host-wide (there is no per-user or per-group managed file) and binds
# every user, the jailer and each worker alike, so it carries only the law:
# the credential reads, `git commit` (unless `allowLocalCommits`) and `git
# push` as deny rules, every hook (the hook
# itself tells a worker from the jailer by group), and the managed-only keys
# that have nowhere else to live (bypass mode off, managed hooks only, the
# mod policy). No sandbox: an unsandboxed jailer session has none, and a
# worker's comes from the jail.
#
# `body = "jail"` is /etc/claude-code/jail-settings.json, the reference copy
# of a worker's rules: the full deny set, the sandbox on with every
# credential, filesystem and network list and no unsandboxed fallback, the
# account sync off. `aj bootstrap` writes every top-level key of it into the
# worker's own ~/.claude/settings.json, and the managed hook refuses a
# worker's tools while that file differs from the reference. It binds a
# worker everywhere, in a cell or outside one, because it lives on the user.
#
# `body = "repo"` is the repo's .claude/settings.json the devenv module
# writes: the cell, or project layer. Allow rules come from `ai-jail.settings`
# (merged by the devenv module), deny rules from `extraDeny`, plus literal
# `denyWrite` paths under the checkout, the project's extra domains, the
# read fence when on, and a few scalars repeated as a belt. Never
# `sandbox.enabled`: that is the jail's. It carries no hooks, no base deny
# list and no credential lists: without the law and the jail a repo
# enforces only what it adds.
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
  # "law", "jail" or "repo".
  body ? "law",
  # "linux" or "wsl"
  platform,
  # Law only, required there: where the hooks live (/etc/claude-code/hooks).
  hookDir ? null,
  allowLocalCommits ? false,
  allowMemoryEdits ? false,
  # Let the claude.ai account's connectors (Gmail, Drive, Notion, ...) load.
  # They are MCP servers that run outside the Bash sandbox, so a session with
  # them can move data out of the repo without any command the hook sees.
  # Jail and repo; the law leaves the jailer's account alone.
  allowConnectors ? false,
  extraDeny ? [ ],
  extraAllowedDomains ? [ ],
  # Law only.
  allowManagedHooksOnly ? true,
  # Jail only. false writes `syncClaudeAiSkills` and `syncClaudeAiPlugins`
  # as false, so no skill or plugin synced from the worker's claude.ai
  # account loads. Honoured from user scope, so it binds from the jail.
  syncClaudeAi ? false,
  # Law only. The whole of `strictKnownMarketplaces` (a list of sources
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
assert lib.assertMsg (lib.elem body [
  "law"
  "jail"
  "repo"
]) "lib/settings.nix: body is law, jail or repo";
assert lib.assertMsg (
  body != "law" || hookDir != null
) "lib/settings.nix: hookDir is required for the law";
assert lib.assertMsg (
  body != "repo" || repoRoot != null
) "lib/settings.nix: repoRoot is required for the repo settings";
let
  denyRules = import ./deny-rules.nix { inherit lib; } {
    inherit allowLocalCommits allowMemoryEdits;
  };
  sshSandbox = import ./ssh-sandbox.nix;
  envGuard = "${hookDir}/env-guard.sh";
  tmuxNotify = "${hookDir}/tmux-notify.sh";
  tmuxWaiting = {
    type = "command";
    command = tmuxNotify;
    args = [ "waiting" ];
    timeout = 5;
  };
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

  schema = {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
  };
  # The jail and the repo carry these; the repo copy repeats them as a belt.
  common = schema // {
    worktree.baseRef = "head";
    # Honoured from any scope, the repo file included; a `true` in user or
    # managed settings cannot be undone here.
    disableClaudeAiConnectors = !allowConnectors;
    includeCoAuthoredBy = false;
  };
  # The sandbox's scalars. `enabled` is the jail's alone: the law has no
  # sandbox, and the repo never writes it, so a worker's sandbox comes from
  # its user settings and the jailer runs without one. The hook refuses a
  # worker's tools unless all three resolve as written here over user,
  # project, local and managed scope (a project or local file outranks the
  # user scope for a scalar).
  sandboxScalars = {
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

  lawBody =
    schema
    // {
      permissions = {
        # Honoured from any scope; a repo can disable bypass mode, never enable it.
        # Managed only in effect (a user file cannot hold it against a flag),
        # so it stays in the law until decided on its own (roadmap item 14).
        disableBypassPermissionsMode = "disable";
        deny = denyRules.law;
      };

      # No `env.CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` anywhere (2026-10-22): a repo
      # file carrying it is ignored ("project-scoped settings can't set this
      # key"), and with it in user scope Claude Code 2.1.300 stops auto-allowing
      # sandboxed Bash commands, so every command with a variable, every read
      # outside the working directory and every write under ~/.claude prompts,
      # which a -p session cannot answer (changelog). What strips secrets from
      # the shell is the explicit `credentials.envVars` deny list in the jail.

      # Registered once, for everyone; the hook applies the law to all and
      # the jail's rules to a member of `agents` only.
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
        # hot-reload, so the hook blocks it for a worker. policy_settings
        # changes cannot be blocked; the hook still runs.
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
        # The orange window: Stop fires when a turn ends and the session
        # waits for the human; Notification covers a permission prompt or
        # dialog mid-turn and the idle reminder. UserPromptSubmit clears.
        Notification = [
          {
            matcher = "permission_prompt|idle_prompt|elicitation_dialog";
            hooks = [ tmuxWaiting ];
          }
        ];
        Stop = [ { hooks = [ tmuxWaiting ]; } ];
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

      # The mod policy, managed only. ai-jailer ships no mods (2026-10-24,
      # docs/sessions.md section 5), so nothing registers a marketplace or
      # enables a plugin (no `extraKnownMarketplaces` key, no
      # `enabledPlugins`, no `prependPlugins`) and every mod is refused. The
      # built-in guard only loads when managed settings exist and reads
      # `allowManagedModsOnly` from here only; with no organisation mod it
      # refuses them all. Binds the jailer too; each key is a candidate for
      # dropping on its own (roadmap item 14).
      pluginConfigs."cc-plugin-sec-default@builtin".options.allowManagedModsOnly = true;
      disableSideloadFlags = true;
      # Which marketplaces a user may add; an empty list adds none.
      strictKnownMarketplaces = extraKnownMarketplaces;
    }
    // lib.optionalAttrs allowManagedHooksOnly { inherit allowManagedHooksOnly; };

  jailBody =
    common
    // {
      permissions = {
        # No defaultMode: the TUI's mode switch (shift+tab) writes
        # permissions.defaultMode into the user file, and pinning it locked
        # a worker out (2026-10-29). The hook, bootstrap and doctor leave
        # that key out of the comparison; what a worker does inside the
        # cell is its own, the rules below bind in every mode.
        disableBypassPermissionsMode = "disable";
        deny = denyRules.jail ++ extraDeny;
      };

      sandbox = {
        enabled = true;
      }
      // sandboxScalars
      // {
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
          # devenv re-fetches the `path:` ai-jailer input on every `direnv export`;
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
    }
    // lib.optionalAttrs (!syncClaudeAi) {
      syncClaudeAiSkills = false;
      syncClaudeAiPlugins = false;
    };

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
        # inside the sandbox (`aj check` case 2, 2026-10-22). The hook
        # still refuses shell writes to them by name.
        denyWrite = map (p: "${repoRoot}/${p}") (
          lib.filter (p: !lib.hasPrefix "devenv.local." p) repoProtected
        );
      };
      network.allowedDomains = extraAllowedDomains;
    };
  };
in
{
  law = lawBody;
  jail = jailBody;
  repo = repoBody;
}
.${body}
