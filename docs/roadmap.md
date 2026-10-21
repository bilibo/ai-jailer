# Roadmap

What exists, what is next, and ideas that are not committed to. Dated
history is in `docs/changelog.md`; the tier, read-fence, customer-module
and launcher-subcommand work is phased in `docs/handoff-tiers.md`.

## Done

- NixOS module: managed settings, hook, sandbox, mod policy, directory
  scoping, per-host options.
- home-manager module: direnv, tmux, `ccmux` (without the broker signal).
- devenv module: generated project settings, host check.
- One settings body for the managed and the repo copy; the repo file
  carries deny rules, every hook and the sandbox, so an unmanaged host runs
  on it alone. The hook blocks `settings.local.json` changes and nested
  `claude` launch flags.
- Tests in `nix flake check`: hook unit tests (154 cases, 180 with
  enforcement roots), the generated repo settings file (15 checks), ccmux
  resolution under both names.
- Own repo with a `flake.nix` exporting the modules, `lib`, the managed
  trees, `packages.direnv` and `packages.devenv` for an unmanaged host, and
  the tests as `checks`.
- Unmanaged Fedora host (2026-10-20): `scripts/bootstrap-fedora.sh` with
  `--check`, `--upgrade` and `--reset`; `scripts/init-repo.sh` (runbook
  section 3); `scripts/live-check.sh` (section 5's live cases). The
  from-zero sequence in runbook section 5 passed end to end on the Fedora
  laptop: first time a real session ran on the repo file alone.
- Host prerequisites settled: direnv 2.38 (override until nixpkgs ships
  it), Nix multi-user without `trusted-users` (the devenv cache goes into
  the root-owned `nix.conf` instead; `--trusted-user` opts in).
- Account connectors off in harness repos (`disableClaudeAiConnectors`
  from the repo file, `harness.allowConnectors` per repo), 2026-10-20.
- Sandbox hardening, the first three items of the 2026-10-20 audit
  (2026-10-21): the bootstrap writes `sandbox.network.strictAllowlist =
  true` into the user-scope `~/.claude/settings.json` (`--no-account-sync`
  adds `syncClaudeAiSkills` and `syncClaudeAiPlugins = false`); the repo
  file lists its own settings, hooks, skills, plugin manifest and `.git`
  hooks and config as literal `denyWrite` paths under `config.devenv.root`,
  which Linux honours; `env.CLAUDE_CODE_SUBPROCESS_ENV_SCRUB = "1"` strips
  credential-shaped variables from every subprocess and the GitHub tokens
  the scrub keeps are `deny` entries. `project-settings-test` 18 checks;
  `live-check` cases 11 (repo write) and 12 (env scrub) written, not yet
  run.
- One CLI instead of three scripts (2026-10-21): `harness` (`pkgs/harness.nix`)
  with `bootstrap`, `upgrade`, `doctor`, `init`, `check`, `reset` and shared
  `--dry-run`, `--yes`, `--verbose`; the script bodies under `pkgs/harness/`,
  shellchecked at build time; `scripts/install.sh` does the root steps
  `nix run` needs and hands over to `harness bootstrap`; a receipt at
  `~/.local/state/claude-nix-harness/receipt.json` drives `reset` and
  `upgrade`; `harness doctor` and `harness init --dry-run` run in
  `nix flake check`.
- Install route for any Linux without Nix (2026-10-19): root `install.sh`
  (nix-installer, profile packages, rc lines, direnv and tmux files), tested
  with every command stubbed (`install-test`, `host-config-test`); not yet
  run on a real distro. Overlaps with `scripts/install.sh` + `harness
  bootstrap`; one of the two goes.
- Secret paths in the hook, path-first (2026-10-21): a command naming a
  secret file is refused unless it is one harmless verb with no pipe,
  substitution or input redirection; the reader-verb list is gone.
  `devenv.local.nix` and `devenv.local.yaml` in `repoProtected`, so the
  file devenv auto-imports without any re-approval cannot be created from
  the sandbox. Bootstrap appends `pkgs/direnv.toml` and `pkgs/tmux.conf`
  instead of its own copies; `reset` without a receipt leaves Nix alone;
  `scripts/install.sh` does dnf, the SELinux label and the daemon socket
  (what `nix run` needs) and hands the rest to `harness bootstrap`; `ccode`
  is gone.
- Read fence prototype (2026-10-21): `harness.readFence` (off by default)
  hides the rest of `$HOME` from sandboxed commands; the hook's env preamble
  puts direnv and devenv on PATH by store path because `~/.nix-profile`, a
  symlink, is not mounted back into a fenced sandbox. Live in the test repo:
  devenv shell loads, `~/.bashrc` and the VS Code settings unreadable,
  `~/.claude` present for the shell snapshot. `project-settings-fenced-test`
  (21 checks).

## Next, in order

0. **One install route.** Decide between root `install.sh` (any Linux,
   stub-tested) and `scripts/install.sh` + `harness bootstrap` (Fedora,
   run end to end); fold the survivor's tests into the other, run it on a
   fresh Ubuntu 24.04.
1. **Root `CLAUDE.md`, under 30 lines.** A session in this checkout has no
   in-repo anchor saying which document owns what; the README's paragraph
   says it for humans. Contents: README for current state, roadmap for
   order, changelog for history, `handoff-tiers.md` for the standing "do
   not activate" rule; and the rule that a closed decision is reopened only
   by a new dated roadmap or changelog entry, never by editing the old one.
   The repo imports its own devenv module since 2026-10-21 (root
   `devenv.nix`), so `harness init` and `harness check` can run against it;
   neither has yet.
2. **Interactive check of the repo-only shape.** `-p` sessions are verified
   (live-check 10/10 on 2026-10-20; cases 11 and 12 added since, unrun).
   Left: a `ccmux` session in the test repo, the trust dialog accepted
   once, hooks seen firing and the tmux window turning orange. The
   Notification matcher names are verified against the hooks reference;
   whether the event fires in tmux is not.
3. **Sandbox hardening**, the rest of the 2026-10-20 audit (runbook
   section 8, "Sandbox limits"); the strict allowlist, the literal
   `denyWrite` paths and the environment scrub are done. Each item is a
   `lib/settings.nix` change with a `project-settings-test` check, or a
   bootstrap change, plus a `live-check` case where the behaviour is only
   visible live:
   1. Read fence, prototyped live in the test repo on 2026-10-21 and kept
      opt-in: `harness.readFence = true` gives `denyRead ["~/"]` plus
      `allowRead` for the repo and the shell-entry paths (`lib/settings.nix`),
      `harness.extraAllowRead` for what the project reads under `$HOME`.
      Left: turn it on in a real repo and watch what breaks (a `path:`
      devenv input and `~/.cargo` are the known cases), then decide the
      default; `harness check` runs case 13 in a fenced repo.
   2. `permissions.blockReadsOutsideWorkingDirectories = true` last. Any
      scope, `true` wins; it stops the Read tool outside the working
      directories, which also stops a session in the test repo reading the
      harness checkout. Decide per tier (handoff phase 2).
   3. Keyring agent sockets: `denyRead` for `/run/user/*/gcr` and
      `/run/user/*/keyring` next to the `/run/WSL` entry. Every unix socket
      is reachable and the gcr address is guessable; `ssh-add -l` against it
      listed the user's keys from inside the sandbox (changelog 2026-10-21);
      whether the agent signs without a desktop prompt was not measured. If
      the wildcard does not take on Linux, the NixOS module writes the
      literal uid path. `harness check`: `ls /run/user/$(id -u)/gcr` fails
      and `ssh-add -l` against the guessed path gets `Could not open a
      connection`. `harness doctor`: warn when `ssh-add -l` lists a key that
      is not `-sk`. With it: the `lib/ssh-sandbox.nix` header (the gate is
      no usable key in any agent, not an unknown address) and a README line
      on `ssh-add -c` and the hardware-key touch timing.
   4. `<repoRoot>/.claude/worktrees` as a literal `denyWrite` in the main
      checkout's file: a child path neither the literal list nor Claude
      Code's cwd-and-parents protection covers. Check first that a worktree
      session's own file (the worktree as `repoRoot`) still writes there;
      if the parent's deny wins, document sibling worktrees as an accepted
      gap.
   5. `.envrc`, `devenv.nix`, `devenv.yaml` and `.env*` in `repoProtected`
      (`devenv.local.*` is in since 2026-10-21): closes the interpreter
      writes the hook cannot see. Check first that the preamble's `direnv
      export` and devenv's first evaluation write none of them;
      `devenv.lock` is the doubtful one. `harness check`: an interpreter
      write gets a permission error, not the hook's message.
   6. `harness check`: `git config core.hooksPath /tmp/h` inside the
      sandbox, expecting a permission error on `.git/config`. If the write
      lands, the literal-path protection has a hole; else runbook section 8
      says the `-c` and `--global` forms are the accepted ones.
4. **devenv-base repo with the `azure` module**: `az` pin, Terraform with
   azurerm/azuread/alz providers, tflint, trivy, and the `AZURE_CONFIG_DIR`
   task under `.git/devenv-base/azure` shared by worktrees.
   `imports: - devenv-base/azure` resolves to `azure/devenv.nix`, same rule
   as `harness/devenv`.
5. **Repo template**: the test repo minus Rust, plus the azure module;
   `harness init` renders it. Convert one real customer repo; confirm
   `az account show` and `terraform plan` inside the sandbox with the
   network allowlist, and record the exact blob hosts the first
   `terraform init` and `trivy` run need.
6. **Reader-only service principal per customer.** The one control that
   holds against every client, including things the hook never sees. Human
   logs it into the repo's `AZURE_CONFIG_DIR`.
7. **Limits suite**: `scripts/live-check.sh` is the first cut. Still to do:
   a throwaway repo (`harness init` into a temporary code root), the cases
   from item 3, the `.devenv/shell-*.sh` litter count over 50 commands,
   `harness doctor --full` running it.
8. **Managed host base config**: a NixOS-WSL base configuration (and later
   a native NixOS one) shipped with the harness, `harness.enable` on both
   modules and nothing else, with the WSL-specific checks (`/run/WSL` and
   `/mnt/c` empty inside the sandbox, `cmd.exe` fails). First time the
   managed layer runs live.
9. **Broker mod** (`docs/sessions.md`): one mod, three stages, each boring
   before the next: observe (`/fleet` from `$.store`, tier in the status
   line, tier contract in the system prompt), propose (`/propose` and a
   `/proposals` pane with accept and reject in the platform session), gate
   (a `tool.call` hook in the platform session that lets through only
   accepted proposals). Deployed through the managed marketplace directory,
   `claude plugin validate` output as the contract. Stage C needs the tier
   split (item 2 of the handoff phases). Only after everything above is
   boring.

## Open questions

- Notification hook: the matcher names (`permission_prompt`, `idle_prompt`,
  `elicitation_dialog`) are in the hooks reference (2026-10-20), with more
  available (`auth_success`, `agent_needs_input`, `agent_completed`).
  Whether the window turns orange in tmux is item 2 above.
- FileChanged matcher: the reference says the value is split on `|` and
  each part is a literal file name in the working directory, so the
  current matcher is right for a session started at the repo root; a
  session started in a subdirectory will not see `devenv.nix` change.
- `AZURE_CONFIG_DIR` shared across worktrees: MSAL lock contention is a
  known risk; revisit if two sessions switch subscriptions under each
  other.
- Per-command env evaluation cost: measure once the azure module is in;
  the SessionStart-only variant is the fallback.
- Account-synced skills on the work host: off (`syncClaudeAiSkills`,
  `syncClaudeAiPlugins`, user or managed scope; the bootstrap's
  `--no-account-sync` writes the `false`s) or on (the default). Today's
  sessions load the official marketplace plugins and the claude.ai skills,
  none of which the harness reviews.

## Ideas, not planned

- Tighten the hook with the gaps listed in the runbook's known-gaps section:
  gh and package publishing as project rules, git exec-vector config keys,
  az transfer verbs, and a fail-closed rule for dynamic shell constructs
  (`$IFS`, `$(`, `base64 -d |`) inside the enforcement roots. Each one
  starts as a test case. Also: stop matching `*/devenv.nix` when the path
  is the harness's own `devenv/devenv.nix`, which the hook refuses today.
- Edit-rule asymmetry: the hook refuses Edit on `.envrc`, `devenv.*`,
  `.claude/settings*`, `.claude/hooks`, `.claude/skills` and
  `.claude-plugin`; Claude Code's own sandbox also protects `.mcp.json`,
  `.claude/agents`, `.claude/commands`, `.claude/workflows` and `.vscode`
  from Bash writes. Mirror that set in `lib/deny-rules.nix` and the hook's
  `config_files`, or write down why not (`.mcp.json` and `.vscode/tasks.json`
  have their own prompts). `.github/workflows/` is separate: CI runs with
  repository secrets, and "agents never push" is the gate today.
- Remote Control (`claude remote-control`, `claude rc`, `--remote-control`,
  `/rc` in a session): the driven session is the local process, so managed
  settings, hook and sandbox apply unchanged; what changes is that anyone
  holding the claude.ai account can prompt a machine with work credentials
  nearby, and attachments from the phone land on disk as `@` references.
  Needs a claude.ai login (Pro, Max, Team, Enterprise; not API key, Bedrock
  or Foundry), so on this laptop it refuses to start today (2.1.300).
  `disableRemoteControl = true` turns it off everywhere it can start,
  including the in-session toggle; the settings reference lists the key as
  any-file scope (checked 2026-10-21), so the repo file can carry it with a
  `harness.allowRemoteControl` option in the `allowConnectors` shape, and
  the managed file makes it final. Which scope wins when they disagree is
  not stated; assume `true` wins as for `disableBypassPermissionsMode` and
  confirm live. Off until the broker and the verification suite exist; the
  hook's nested-launch rule does not need the flag once the key is set.
- nix-darwin module: same `lib/`, managed settings under
  `/Library/Application Support/ClaudeCode/`, seatbelt sandbox keys; the
  glob `denyWrite` entries apply there.
- Container route: built and set aside in the claude-nix-harness-container
  repo (same `lib/`, root-owned store behind a nix-daemon, devcontainer
  files per engine; never run under podman or VS Code). The WSL tier does
  not use it; NixOS-WSL builds its distro tarball from the NixOS module.
- A parser-based second guard (cc-safety-net rulebooks) beside the regex
  hook.
