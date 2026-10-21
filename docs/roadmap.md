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
- Root `CLAUDE.md` (2026-10-21), under 30 lines: which document owns what,
  the handoff's standing rules, the closed-decision rule, how a session runs
  the checks. First `harness doctor` and `harness init --dry-run` against
  the checkout: init leaves `devenv.yaml`, `devenv.nix` and `.envrc` alone
  and would add three `.gitignore` lines that `.claude/` already covers;
  doctor's repo report and VS Code lines were false from inside a session
  (the sandbox masks `.claude/settings.json` as a character device, and the
  host's `code` dies on the shell's `LD_LIBRARY_PATH`), now reported as
  such (`harness-doctor-test` 27 checks). `harness check` against the
  checkout still has not run: it needs a terminal, not a session.
- One install route (2026-10-21): `scripts/install.sh` + `harness
  bootstrap` survives; the root `install.sh` is gone and what only it did
  moved over. The script: the nix-installer where Fedora's packages are
  not there (before `nix run` exists), the checkout as the default ref,
  `harness init` on the checkout at the end (the old shell build and
  self-check). bootstrap: no Fedora-only preflight, the user-namespace
  sysctl offered on its own and declinable, the direnv hook in a
  `~/.bashrc` that does not source `~/.bashrc.d` and in `~/.zshrc`, the
  tmux block in the file tmux reads (`~/.tmux.conf` when it exists),
  flakes in `nix.conf` where the installer left them off; `reset` undoes
  the sysctl and runs the installer's uninstaller. `install-test` rewritten
  for the script (both routes, 44 checks), `harness-bootstrap-test` new
  (94 checks: rc-file layouts, nix.conf, the sysctl, idempotency, reset). Run on nothing but the stubs so far; the runbook's
  fresh-distro list (section 5) is the verification, on Ubuntu 24.04.
- Audit fixes (2026-10-21, staged; in once committed): two whole-repo
  audits (Opus, then Fable), every hook claim re-run against the built
  hook, worked by three sessions the same evening (changelog). The hook
  refuses working-tree discards and force-moves (`checkout .`/`-f`,
  `switch -f`/`-C`, `checkout -B`, `branch -f`, `tag -f`, `worktree
  remove -f`), checks edits on the link target as well as the name, and
  covers `~/.bashrc.d`, `~/.local/bin` and every `file -f` spelling;
  `~/.aws`, `~/.config/gh` and `~/.git-credentials` are hidden by every
  layer. `harness init` asks before loading repo files it did not write;
  `harness upgrade` builds before it removes; the no-receipt `reset`
  branch, the profile-ccmux ref fallback and `lib/project-settings.nix`
  are gone; the direnv version check lives in `pkgs/direnv.nix` only.
  hook-test 241 cases, project-settings-test 22 (23 fenced),
  harness-bootstrap-test 101, harness-init-test 24; `nix flake check`
  green on the combined tree.
- First live `harness check` (2026-10-22, Ubuntu, 9 of 12): the devenv
  shell loads inside the sandbox again (`devenv.local.*` out of the literal
  `denyWrite` list), the environment scrub lives in the managed copy and
  the user-scope keys the bootstrap writes (a repo file's copy is ignored),
  case 11 reads the sandbox's mask as the refusal it is (changelog).

## Target flow (2026-10-21)

What the pieces add up to, and what is missing for it:

1. One installer per host: `curl -fsSL .../scripts/install.sh | bash -s
   -- --yes` (or `scripts/install.sh` from a clone) does the root and
   pre-Nix work, then `harness bootstrap` the user side, on Fedora,
   Ubuntu and NixOS, each also under WSL.
2. The harness checkout is the command center: its own devenv shell,
   `ccmux` in it, the session where the human accepts what other
   sessions propose.
3. `harness init <customer>/<repo>` per project: a standard
   `devenv.nix` a non-Nix user can add tools to.
4. `ccmux` sessions per project, set on tasks by hand or by the command
   center; what their rules refuse, they propose to the command center
   instead of working around.

Status against it: 1 runs end to end on Fedora 44 and on Ubuntu 26.10
(2026-10-22: install, bootstrap, `harness init` on the checkout, `harness
check`, `ccmux`; changelog); nothing detects NixOS or WSL. 2 works by convention
(CLAUDE.md contracts and `SendMessage`, as on 2026-10-21 when three
sessions worked the audit board); the checkout is itself under the
customer rules (the hook refuses its `devenv.nix`) until the tier split.
3 works; the template has no guide. 4 works by hand.

The gaps, in order:

- A. **Host detection** (`scripts/install.sh`, once; exported to bootstrap
  and init). Fedora 44+ as today. NixOS (`/etc/NIXOS` exists): no
  installer, and bootstrap must not write `/etc/nix/nix.conf` (a store
  symlink the next rebuild restores): print the `nix.settings` lines for
  the devenv cache instead, or point at the NixOS and home modules (the
  README's managed row), then do the user steps. WSL
  (`/proc/sys/fs/binfmt_misc/WSLInterop` or `WSL_DISTRO_NAME`): check
  that systemd runs in the distro (`[boot] systemd=true` in
  `/etc/wsl.conf`; the nix-installer's daemon needs it, else
  `--init none`: verify which), skip the `environment.d` step (no
  Linux GUI login), and `harness init` writes `harness.platform =
  "wsl";` into `devenv.nix` so `/mnt/c` and `/run/WSL` are hidden from
  the sandbox; today no unmanaged WSL repo gets that. NixOS-WSL stays the
  module route (item 7). Tests: install-test and harness-bootstrap-test
  cases with a fake `ID=nixos` os-release plus a marker path, and a fake
  WSL marker (`HARNESS_*` overrides, as the other system paths have).
- B. **Ubuntu for real**: runbook section 5's fresh-distro list on Ubuntu
  24.04, done under WSL so it verifies A's WSL branch on the same run.
- C. **A guide to the project devenv for non-Nix users**
  (`docs/project-devenv.md`, linked from the README and from the
  `devenv.nix` `harness init` writes): what the four files are and which
  ones a human edits; adding a tool (`packages = [ pkgs.terraform ];`,
  names from search.nixos.org/packages); a language toolchain
  (`languages.rust.enable = true;`); environment variables (`env.X =
  "...";`, never secrets: README "Where project configuration goes");
  project allow rules (`harness.settings.permissions.allow`); network
  hosts for the sandbox (`harness.extraAllowedDomains`); unfree packages
  (`allow_unfree: true`); the `direnv allow` prompt after every change
  and why (`require_allowed`); and the agent's side: it proposes the
  diff, the human applies it. The template gains one commented line per
  case pointing at the guide. Phase 3's `lang` option (handoff) shortens
  it later; the guide comes first. Since 2026-10-21 the template lists
  every harness option commented out; the guide is still to write.
- D. **Command center as a tier**: handoff phase 2 (tiers: the checkout
  and `~/nixos-config` as platform roots, `HARNESS_TIER` from `ccmux`),
  then the broker's stage B (item 8: `/propose`, the `/proposals` pane).
  No new work beyond those two; the order is phase 2 first.

## Next, in order

0. **Audit follow-ups (2026-10-21).** What the audit fixes left open or
   turned up. The human's, in this order:
   1. Review and commit the staged set (17 files). One choice inside it:
      `~/.config/gh` in `denyRead` (`lib/settings.nix`) ends `gh` reads
      in sessions as well as the token leak; drop that line to keep them,
      and accept that `gh auth login` without a keyring puts a push token
      in reach again.
   2. Done 2026-10-21: `devenv/devenv.nix` imports `pkgs/direnv.nix`.
   3. One installer, decided 2026-10-21 (Target flow, below):
      `scripts/install.sh` owns every root and pre-Nix step, `harness
      bootstrap` the user side. In `pkgs/harness/bootstrap.sh`, from
      `root_steps`: delete the `ROOT_RPMS` dnf loop, the SELinux block and
      the daemon-socket block, and the `ROOT_RPMS` array; keep the
      nix.conf block (the devenv cache) and `userns_steps`. `reset` keeps
      undoing them from the receipt (install.sh hands them over in
      `HARNESS_ROOT_PACKAGES`/`HARNESS_ROOT_STEPS`); `doctor` keeps
      reporting SELinux and the socket. `tests/harness-bootstrap-test.sh`
      case 11 (dnf on Fedora) goes; the Fedora host line check moves to a
      doctor-only case. Fix the header (lines 9-35: "Root is needed for
      dnf (Fedora)...").
   4. `CLAUDE.md`, section "Checks": the `git archive` copy misses
      untracked files the flake references. Replace "run it on a `git
      archive` copy" with a copy of the regular files only (the sandbox
      masks untracked dotfiles as device nodes and `tar` stops on them):
      ```
      git ls-files -co --exclude-standard -z \
        | while IFS= read -r -d '' f; do [ -f "$f" ] && printf '%s\0' "$f"; done \
        | tar --null -T - -cf - | tar -xf - -C <dir>
      nix flake check path:<dir>
      ```
      The same filter goes into the memory note `nix-build-from-tree-copy`
      (`~/.claude/projects/-home-raul-code-claude-nix-harness/memory/`),
      which a session cannot write.
   5. `tests/harness-bootstrap-test.sh` line 63: `PATH="$tmp/bin:$PATH"`
      becomes `PATH="$tmp/bin"`; the harness wrapper prepends its own
      store tools (`pkgs/harness.nix` runtimeInputs), so the stubs are all
      it needs. Measured 2026-10-21 on this laptop: 67 passed, 34 failed
      as is (the host's `getenforce` and `code`); 101 passed, 0 failed
      with the change. Drop "and no getenforce or code on PATH, which the
      Nix build sandbox guarantees" from the header (lines 14-16).
   6. `pkgs/harness/init.sh`, the foreign-file block (lines 192-199): a
      foreign `devenv.lock` is approved by the second `direnv allow`
      without being shown, and it pins every input, nixpkgs included.
      When `devenv.lock` existed before this run, print its inputs under
      the same `==>` header instead of the raw file (it is not readable),
      and count it in `foreign` so the y/N covers it:
      ```
      jq -r '.nodes | to_entries[] | select(.value.locked) | .value.locked as $l
        | "  \(.key): \($l.type):\($l.owner // "")\(if $l.owner then "/" else "" end)\($l.repo // $l.path // $l.url // "") @ \($l.rev // $l.narHash // "?")"' devenv.lock
      ```
      (on this repo's lock: `devenv: github:cachix/devenv @ a86a087…`,
      `nixpkgs: github:NixOS/nixpkgs @ fe13242…`). Check for the lock in
      that block, before the first `direnv allow`: the first load creates
      one, which is the harness's own. Test in `tests/harness-init-test.sh` beside the
      existing foreign-file case: a repo with its own lock, its input
      line printed, no `direnv allow` without `--yes`.
   7. Done 2026-10-21: hook refuses `git checkout <ref> <path>...` (changelog).
   8. `pkgs/harness/check.sh`, a case 14 before the dry-run cut (line
      151): the sandbox hides `~/.git-credentials` on its own. The hook
      refuses the path by name, so the command spells it around the
      `cred_files` regex: `f=~/.git-; wc -c "${f}credentials"`. Create
      the file with a fake line first when absent (`https://x:live-check@
      example.invalid`) and remove it after; leave a real one alone.
      Expect the sandbox's answer (a masked file reads as empty, `^0 `,
      or a permission error: confirm which on the first run), forbid
      `live-check`. Then the header count ("twelve" and "thirteen")
      goes up by one.
   Not planned: `~/.kube/config` and `~/.docker/config.json` the same way
   as `~/.aws`, until a harness host holds them.
1. **Interactive check of the repo-only shape.** `-p` sessions are verified
   (live-check 10/10 on 2026-10-20; cases 11 and 12 added since, unrun).
   Left: a `ccmux` session in the test repo, the trust dialog accepted
   once, hooks seen firing and the tmux window turning orange (`ccmux` on
   the checkout runs on the Ubuntu laptop since 2026-10-22; the hook
   firing and the orange window are still unobserved). The
   Notification matcher names are verified against the hooks reference;
   whether the event fires in tmux is not.
2. **Sandbox hardening**, the rest of the 2026-10-20 audit (runbook
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
   5. Answered 2026-10-22, no: a literal `denyWrite` entry is masked as an
      unreadable device node (changelog), so a file direnv or devenv reads
      can never be one; `devenv.local.*` left the list that day and the
      interpreter-write gap moved to item 2.7. As written: `.envrc`,
      `devenv.nix`, `devenv.yaml` and `.env*` in `repoProtected`
      (`devenv.local.*` is in since 2026-10-21): closes the interpreter
      writes the hook cannot see. Check first that the preamble's `direnv
      export` and devenv's first evaluation write none of them;
      `devenv.lock` is the doubtful one. `harness check`: an interpreter
      write gets a permission error, not the hook's message.
   6. `harness check`: `git config core.hooksPath /tmp/h` inside the
      sandbox, expecting a permission error on `.git/config`. If the write
      lands, the literal-path protection has a hole; else runbook section 8
      says the `-c` and `--global` forms are the accepted ones.
   7. `devenv.local.nix` and `devenv.local.yaml` can be created by an
      interpreter write the hook does not see, and devenv imports them on
      the next evaluation without a `direnv allow` (the literal `denyWrite`
      that closed this broke the shell, 2026-10-22). Candidate: the `.envrc`
      the template writes fails the load when either file exists (a test
      before `use devenv`), so a harness repo never carries them; the
      checkout's own `.envrc` the same, by hand. `harness check`: a
      `python3` write creating one gets the next command's preamble failing
      loudly, not a silently imported file.
3. **devenv-base repo with the `azure` module**: `az` pin, Terraform with
   azurerm/azuread/alz providers, tflint, trivy, and the `AZURE_CONFIG_DIR`
   task under `.git/devenv-base/azure` shared by worktrees.
   `imports: - devenv-base/azure` resolves to `azure/devenv.nix`, same rule
   as `harness/devenv`.
4. **Repo template**: the test repo minus Rust, plus the azure module;
   `harness init` renders it. Convert one real customer repo; confirm
   `az account show` and `terraform plan` inside the sandbox with the
   network allowlist, and record the exact blob hosts the first
   `terraform init` and `trivy` run need.
5. **Reader-only service principal per customer.** The one control that
   holds against every client, including things the hook never sees. Human
   logs it into the repo's `AZURE_CONFIG_DIR`.
6. **Limits suite**: `scripts/live-check.sh` is the first cut. Still to do:
   a throwaway repo (`harness init` into a temporary code root), the cases
   from item 2, the `.devenv/shell-*.sh` litter count over 50 commands,
   `harness doctor --full` running it.
7. **Managed host base config**: a NixOS-WSL base configuration (and later
   a native NixOS one) shipped with the harness, `harness.enable` on both
   modules and nothing else, with the WSL-specific checks (`/run/WSL` and
   `/mnt/c` empty inside the sandbox, `cmd.exe` fails). First time the
   managed layer runs live.
8. **Broker mod** (`docs/sessions.md`): one mod, three stages, each boring
   before the next: observe (`/fleet` from `$.store`, tier in the status
   line, tier contract in the system prompt), propose (`/propose` and a
   `/proposals` pane with accept and reject in the platform session), gate
   (a `tool.call` hook in the platform session that lets through only
   accepted proposals). Deployed through the managed marketplace directory,
   `claude plugin validate` output as the contract. Stage C needs the tier
   split (item 2 of the handoff phases). Only after everything above is
   boring. Groundwork in since 2026-10-21 (changelog): `lib/mods.nix`, the
   marketplace and `enabledPlugins` wiring, `harness.mods`, and the part of
   stage A that needs no tier (the `$.store` row, `/fleet`).
   `tests/mod-validate-test.sh` over `managed-mods` passes (2026-10-21, by
   hand); the first managed-host load is still to do. The tier line, stage
   B and stage C wait as before.

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
  `syncClaudeAiPlugins`, user or managed scope; the bootstrap's
  `--no-account-sync` writes the `false`s) or on (the default). Today's
  sessions load the official marketplace plugins and the claude.ai skills,
  none of which the harness reviews.
- `LD_LIBRARY_PATH` inside a session carries a Nix alsa-lib path that
  neither devenv, direnv nor the harness exports (2026-10-21); the host's
  `code` loads `librt` from the Nix glibc through it and dies. Trace the
  exporter (the launcher, the terminal, Claude Code itself) before the
  managed host, where more host binaries run from sessions.

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
