# Roadmap

What exists, what is next, and ideas that are not committed to. Dated
history is in `docs/changelog.md`; the tier, read-fence, customer-module
and launcher-subcommand work is phased in `docs/handoff-tiers.md`.

## Done

- NixOS module: managed settings, hook, sandbox, mod policy, directory
  scoping, per-host options.
- home-manager module: direnv, tmux, `ccmux` (without the broker signal).
- devenv module: generated project settings, host check, optional image.
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

## Next, in order

1. **Interactive check of the repo-only shape.** `-p` sessions are verified
   (live-check 10/10). Left: a `ccmux` session in the test repo, the trust
   dialog accepted once, hooks seen firing and the tmux window turning
   orange. The Notification matcher names are verified against the hooks
   reference; whether the event fires in tmux is not.
2. **Sandbox hardening**, from the 2026-10-20 audit (runbook section 8,
   "Sandbox limits"), cheapest and safest first. Each item is a
   `lib/settings.nix` change with a `project-settings-test` check, or a
   bootstrap change, plus a `live-check.sh` case where the behaviour is
   only visible live:
   1. `sandbox.network.strictAllowlist = true` in the user-scope
      `~/.claude/settings.json`, written by `bootstrap-fedora.sh` (the key
      is user-or-managed scope; the repo file cannot carry it). Same place
      for `syncClaudeAiSkills` and `syncClaudeAiPlugins` if the work host
      should not load account-synced skills; decision for Raul.
   2. Literal `denyWrite` paths in place of the `**/` globs Linux skips:
      the test repo's own `.claude/settings.json`, `.git/hooks`,
      `.git/config` via `config.devenv.root` at devenv eval time. Keep the
      globs for macOS.
   3. Read fence: `denyRead ["~/"]` plus `allowRead` for the repo,
      `~/.nix-profile`, `~/.local/state/nix`, `~/.cache/nix`,
      `~/.cache/devenv`, `~/.local/share/direnv` ("the narrower path wins").
      Prototype in the test repo first: if the hook's `direnv export`
      preamble stops working inside the sandbox, every command runs without
      the devenv shell. Live cases: a sibling-repo read, a credential read
      through a reader the hook does not list.
   4. Environment scrub: `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB`, or a longer
      `credentials.envVars` deny list.
   5. `permissions.blockReadsOutsideWorkingDirectories = true` last. Any
      scope, `true` wins; it stops the Read tool outside the working
      directories, which also stops a session in the test repo reading the
      harness checkout. Decide per tier (handoff phase 2).
   6. Accepted, not closable from a repo: every unix socket reachable
      (`allowAllUnixSockets` is all-or-none on Linux).
3. **One CLI instead of three scripts.** The installer survey (2026-10-20:
   azd `install-azd.sh`, Determinate `nix-installer`, `rustup-init.sh`, uv
   `install.sh`) gives the shape: a shim that only gets the real tool
   running, then a versioned tool with subcommands, a plan or dry-run, a
   receipt that drives uninstall, and a self-test. Here the tool is
   installable by Nix, so no compiled installer is needed:
   - `scripts/install.sh`, curl-able, under 100 lines: the pre-Nix root
     steps only (`dnf install nix nix-daemon ...`, the `nix.conf` block, the
     SELinux label, the socket), then
     `exec nix run <harness>#harness -- bootstrap "$@"`.
   - `pkgs/harness.nix`: one `writeShellApplication` named `harness` with
     `bootstrap`, `doctor` (today's `--check`, plus `claude doctor` and the
     repo's symlink and hook state), `init` (today's `init-repo.sh`),
     `check` (today's `live-check.sh`), `upgrade`, `reset`; shared
     `--dry-run`, `--yes`, `--verbose`. The script bodies move under
     `pkgs/harness/` unchanged, so shellcheck keeps covering them.
   - A receipt, `~/.local/state/claude-nix-harness/receipt.json`: packages
     added, files written, root steps done, harness revision. `reset` and
     `upgrade` read it instead of a hard-coded list (what azd's uninstall
     lacks and the Determinate installer has).
   - `ccmux` stays the launcher. `harness doctor` is what the handoff
     called `ccmux doctor`; `harness init` is the first half of `ccmux new`.
   - Tests: `harness doctor` and `harness init --dry-run` under a temp HOME
     in `nix flake check`; `harness check` as a `nix run` app, it needs
     the API.
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
   from item 2, the `.devenv/shell-*.sh` litter count over 50 commands,
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
  Whether the window turns orange in tmux is item 1 above.
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
  user or managed scope) or on. Today's sessions load the official
  marketplace plugins and the claude.ai skills, none of which the harness
  reviews.

## Ideas, not planned

- Tighten the hook with the gaps listed in the runbook's known-gaps section:
  gh and package publishing as project rules, git exec-vector config keys,
  az transfer verbs, and a fail-closed rule for dynamic shell constructs
  (`$IFS`, `$(`, `base64 -d |`) inside the enforcement roots. Each one
  starts as a test case. Also: stop matching `*/devenv.nix` when the path
  is the harness's own `devenv/devenv.nix`, which the hook refuses today.
- Remote Control (`claude remote-control`): the driven session is the local
  process, so managed settings, hook and sandbox apply unchanged; what
  changes is that anyone holding the claude.ai account can prompt a machine
  with work credentials nearby. Per-host opt-in, off on a managed host until
  the broker and the verification suite exist; check whether managed
  settings can disable it outright.
- nix-darwin module: same `lib/`, managed settings under
  `/Library/Application Support/ClaudeCode/`, seatbelt sandbox keys; the
  glob `denyWrite` entries apply there.
- Running the `harness.container.enable` image (it builds today) for a
  project that must not touch the host at all: podman needs
  `--security-opt unmask=/proc/*` so bubblewrap works inside, and
  `--userns=keep-id` plus the user-level podman socket when launched from
  `vscode-fhs`.
- A parser-based second guard (cc-safety-net rulebooks) beside the regex
  hook.
