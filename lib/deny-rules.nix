# Deny rules are prefix/glob matches that hold in every permission mode and
# against user-tier mods, but `git -C . push`, `bash -c '...'` and scripts
# that open files themselves get past them; the hook and the sandbox exist
# for that.
#
# Two lists (roadmap item 14, 2026-10-28). `law` binds everyone on the host,
# the jailer's own sessions included: the credential reads, `git commit`
# (unless the host allows local commits) and `git push`,
# nothing else; it goes into the managed file. `jail` is the full set for a
# worker (a member of `agents`); it goes into the worker's user settings,
# where the managed hook checks it against the managed tree's reference copy.
# Deny lists merge across scopes, so a worker gets both.
#
# Path rules use `**/` or `~/`: in user-scope settings a leading `/` anchors
# at ~/.claude, not at the project root.
{ lib }:
{
  allowLocalCommits ? false,
  # Globs cannot express "everything but", so this swaps the blanket
  # ~/.claude rule for an enumerated list; the hook keeps the rest of
  # ~/.claude/projects (transcripts) closed.
  allowMemoryEdits ? false,
}:
let
  # Bare form and argument form both, since `git commit *` does not match a
  # plain `git commit` with no arguments.
  bash =
    cmds:
    lib.concatMap (c: [
      "Bash(${c})"
      "Bash(${c} *)"
    ]) cmds;

  # The law's half: what reads a credential. In-repo secrets, the user's
  # own Claude login, the GitHub tokens on disk, Azure's token cache, ssh.
  credentialReads = [
    "Read(**/.env)"
    "Read(**/.env.*)"
    "Read(**/*.tfvars)"
    "Read(**/*.tfvars.json)"
    "Read(**/*.tfstate)"
    "Read(**/*.tfstate.backup)"
    "Read(**/.git/devenv-base/**)"
    "Read(~/.azure/**)"
    "Read(~/.ssh/**)"
    "Read(~/.config/gh/**)"
    "Read(~/.git-credentials)"
    "Read(~/.claude/.credentials.json)"
    "Read(~/.claude.json)"
  ];
  # No `Read(**/.devenv/**)` or `Read(**/.direnv/**)` for the workers (tried
  # and reverted 2026-10-29): Claude Code merges Read(...) deny rules into
  # the sandbox's denyRead and expands the glob through symlinked
  # directories, so `.devenv/profile` and `.devenv/bash-bash` put a tmpfs
  # over the devenv profile and the bash package in the store, and every
  # sandboxed command died with `bwrap: execvp /bin/bash: No such file`.
  # `Read(**/.terraform/**)` went the same way (dropped 2026-10-29, roadmap
  # item 14): it would mask a cell's providers, and the state file inside
  # that directory is covered by `**/*.tfstate` above; the hook's rule 2
  # blocks state writes.

  credentials =
    credentialReads
    ++ bash [
      "az login"
      "az logout"
      "az account set"
      "az account clear"
      "az account get-access-token"
      "az ad sp credential"
      "az keyvault secret"
      "az keyvault key"
      "az keyvault certificate"
    ];

  system =
    bash [
      "sudo"
      "doas"
      "su"
      "pkexec"
      "run0"
      "nix profile"
      "nix-env"
      "nixos-rebuild"
      "nh os switch"
      "nh os boot"
      "nh os test"
      "nh home switch"
      "nix-channel"
      "nix-collect-garbage"
      "nix upgrade-nix"
      "home-manager switch"
      "systemctl"
      "wsl.exe"
      "cmd.exe"
    ]
    ++ [
      "Bash(*.exe)"
      "Bash(*.exe *)"
      "Bash(powershell*)"
      "Bash(pwsh*)"
    ];

  plugins = bash [ "claude plugin" ] ++ [
    "Bash(claude * --plugin-dir *)"
    "Bash(claude * --plugin-url *)"
  ];

  # A `Read` deny also blocks Edit/Write (2.1.228+); the Edit rules stay
  # explicit anyway.
  claudeHome =
    if allowMemoryEdits then
      [
        "Edit(~/.claude/*.json)"
        "Edit(~/.claude/*.md)"
        "Edit(~/.claude/.credentials.json)"
        "Edit(~/.claude/settings.json)"
        "Edit(~/.claude/settings.local.json)"
        "Edit(~/.claude/CLAUDE.md)"
        "Edit(~/.claude/keybindings.json)"
        "Edit(~/.claude/hooks/**)"
        "Edit(~/.claude/skills/**)"
        "Edit(~/.claude/plugins/**)"
        "Edit(~/.claude/commands/**)"
        "Edit(~/.claude/agents/**)"
        "Edit(~/.claude/rules/**)"
        "Edit(~/.claude/output-styles/**)"
        "Edit(~/.claude/workflows/**)"
        "Edit(~/.claude/routines/**)"
        "Edit(~/.claude/local/**)"
        "Edit(~/.claude/projects/*/*.jsonl)"
      ]
    else
      [ "Edit(~/.claude/**)" ];

  # Files that run code at the user's next shell, git or tmux start, outside
  # the sandbox. `~/.config/**` matches the sandbox's denyWrite of ~/.config.
  # The same list as the hook's user-config case (hooks/env-guard.sh,
  # check_edit); change both.
  userConfig = claudeHome ++ [
    "Edit(~/.bashrc)"
    "Edit(~/.bash_profile)"
    "Edit(~/.bash_login)"
    "Edit(~/.profile)"
    "Edit(~/.zshrc)"
    "Edit(~/.zprofile)"
    "Edit(~/.zshenv)"
    "Edit(~/.zlogin)"
    "Edit(~/.gitconfig)"
    "Edit(~/.tmux.conf)"
    "Edit(~/.ssh/**)"
    "Edit(~/.config/**)"
    "Edit(~/.bashrc.d/**)"
    "Edit(~/.local/bin/**)"
  ];

  gitHistory = bash (
    lib.optionals (!allowLocalCommits) [ "git commit" ]
    ++ [
      "git push"
      "git reset"
      "git rebase"
      "git merge"
      "git cherry-pick"
      "git revert"
      "git restore"
      "git checkout --"
      # Discard uncommitted work or move a ref by force.
      "git checkout -f"
      "git checkout ."
      "git switch -f"
      "git switch --discard-changes"
      "git branch -f"
      "git branch --force"
      "git tag -f"
      "git worktree remove --force"
      # Deny patterns keep case: these are not the harmless -c / -b.
      "git switch -C"
      "git checkout -B"
      "git clean"
      "git stash drop"
      "git stash clear"
      "git stash pop"
      "git branch -D"
      "git branch -d"
      "git tag -d"
      "git reflog expire"
      "git filter-branch"
      "git filter-repo"
      "git update-ref"
      "git symbolic-ref"
      "git gc"
      "git prune"
      "git am"
    ]
  );

  cloudWrite =
    bash [
      "terraform apply"
      "terraform destroy"
      "terraform import"
      "terraform state"
      "terraform taint"
      "terraform untaint"
      "terraform force-unlock"
      "tofu apply"
      "tofu destroy"
      "tofu import"
      "tofu state"
      "terragrunt apply"
      "terragrunt destroy"
      "az deployment"
      "az rest"
      "az group create"
      "az group delete"
      "func azure functionapp publish"
      "pulumi up"
      "pulumi destroy"
      "bicep publish"
    ]
    ++ [
      "Bash(az * create *)"
      "Bash(az * delete *)"
      "Bash(az * update *)"
      "Bash(az * set *)"
      "Bash(az * start *)"
      "Bash(az * stop *)"
      "Bash(az * restart *)"
      "Bash(az * purge *)"
      "Bash(az * assign *)"
      "Bash(az * remove *)"
      "Bash(az * regenerate *)"
      "Bash(az * import *)"
    ];

  # The agent proposes changes to these as a diff in its reply, never writes them.
  projectConfigPaths = [
    "devenv.nix"
    "devenv.yaml"
    "devenv.lock"
    "devenv.local.*"
    ".envrc"
    ".env"
    ".env.*"
    ".claude/settings.json"
    ".claude/settings.local.json"
    ".claude/hooks/**"
    # Drop this one only if agents must author skills; enable
    # `allowManagedHooksOnly` or `strictPluginOnlyCustomization` first.
    ".claude/skills/**"
    ".claude-plugin/**"
  ];
  projectConfig = map (p: "Edit(**/${p})") projectConfigPaths;
in
{
  law =
    credentialReads ++ bash (lib.optionals (!allowLocalCommits) [ "git commit" ] ++ [ "git push" ]);
  jail = credentials ++ system ++ plugins ++ userConfig ++ gitHistory ++ cloudWrite ++ projectConfig;
}
