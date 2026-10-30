# Roadmap

What exists, what is next, and ideas that are not committed to. Dated
history is in `docs/changelog.md`.

## Done

What exists is in the README (the host and lockdown tables); when and why
it changed is in `docs/changelog.md`. The itemised list that stood here
until 2026-10-26 is in git: `git show 8e38390:docs/roadmap.md`.

Renamed on 2026-10-28 (changelog): the repo and flake are `ai-jailer`, the
CLI `aj`, the launcher `ajmux`, and a governed repo is a jail with
`ai-jail.*` options. Items below written before that day keep the names
they had (`harness.role`, `harness.workers`, ...).

## Target flow (2026-10-21)

What the pieces add up to, and what is missing for it:

1. One installer per host: `curl -fsSL .../scripts/install.sh | bash -s
   -- --yes` (or `scripts/install.sh` from a clone) does the root and
   pre-Nix work, then `aj bootstrap` the user side, on Fedora,
   Ubuntu and NixOS, each also under WSL.
2. The ai-jailer checkout is the command center: its own devenv shell,
   `ajmux` in it, the session where the human accepts what other
   sessions propose.
3. `aj init <org>/<repo>` per project: a standard
   `devenv.nix` a non-Nix user can add tools to.
4. `ajmux` sessions per project, set on tasks by hand or by the command
   center; what their rules refuse, they propose to the command center
   instead of working around.

Status against it: 1 runs end to end on Fedora 44 and on Ubuntu 26.10
(2026-10-22: install, bootstrap, `aj init` on the checkout, `aj
check`, `ajmux`; changelog); NixOS is detected since 2026-10-23 (gap A, the
NixOS half), WSL detection is stubbed. 2 works by convention
(CLAUDE.md contracts and `SendMessage`, as on 2026-10-21 when three
sessions worked the audit board); since 2026-10-24 the checkout has its
own role (`center`), but its hook is a work repo's, so it still refuses
its `devenv.nix` and the module source `devenv/devenv.nix`.
3 works, with a guide since 2026-10-24 (gap C). 4 works by hand.
Added 2026-10-27: item 11 replaces the center and the role with one
Linux user per org and host-wide managed rules; point 2 above is
superseded by it.

The gaps, in order:

- A. **Host detection**: NixOS half done 2026-10-23, WSL detection
  stubbed, live WSL pending (changelog). As written on 2026-10-21:
  (`scripts/install.sh`, once; exported to bootstrap
  and init). Fedora 44+ as today. NixOS (`/etc/NIXOS` exists): no
  installer, and bootstrap must not write `/etc/nix/nix.conf` (a store
  symlink the next rebuild restores): print the `nix.settings` lines for
  the devenv cache instead, or point at the NixOS and home modules (the
  README's managed row), then do the user steps. 2026-10-27, item 12:
  bootstrap runs the root steps on NixOS too; the modules are gone. WSL
  (`/proc/sys/fs/binfmt_misc/WSLInterop` or `WSL_DISTRO_NAME`): check
  that systemd runs in the distro (`[boot] systemd=true` in
  `/etc/wsl.conf`; the nix-installer's daemon needs it, else
  `--init none`: verify which), skip the `environment.d` step (no
  Linux GUI login), and `aj init` writes `ai-jail.platform =
  "wsl";` into `devenv.nix` so `/mnt/c` and `/run/WSL` are hidden from
  the sandbox; today no unmanaged WSL repo gets that. NixOS-WSL stays the
  module route (item 7). Tests: install-test and aj-bootstrap-test
  cases with a fake `ID=nixos` os-release plus a marker path, and a fake
  WSL marker (`AI_JAILER_*` overrides, as the other system paths have).
- B. **Ubuntu for real**: runbook section 5's fresh-distro list on Ubuntu
  24.04, done under WSL so it verifies A's WSL branch on the same run.
- C. **A guide to the project devenv for non-Nix users**: written
  2026-10-24 (changelog), every case below; the template links it in its
  header and gains the `packages`, `languages` and `env` lines. As written
  on 2026-10-21:
  (`docs/project-devenv.md`, linked from the README and from the
  `devenv.nix` `aj init` writes): what the four files are and which
  ones a human edits; adding a tool (`packages = [ pkgs.terraform ];`,
  names from search.nixos.org/packages); a language toolchain
  (`languages.rust.enable = true;`); environment variables (`env.X =
  "...";`, never secrets: README "Where project configuration goes");
  project allow rules (`ai-jail.settings.permissions.allow`); network
  hosts for the sandbox (`ai-jail.extraAllowedDomains`); unfree packages
  (`allow_unfree: true`); the `direnv allow` prompt after every change
  and why (`require_allowed`); and the agent's side: it proposes the
  diff, the human applies it. The template gains one commented line per
  case pointing at the guide. The org module's `lang` option (item 9) shortens
  it later; the guide comes first. Since 2026-10-21 the template lists
  every ai-jail option commented out; the guide is still to write.
- D. **Command center as a tier**: realised 2026-10-24 as `harness.role`
  (`docs/sessions.md` section 3). `center` is this
  checkout: the same deny rules and hook as a work repo, no sandbox, Bash
  prompted, memory on, `AI_JAILER_ROLE=center` carried by `ajmux`. `work`
  is everywhere else. The checkout imports the module pinned from GitHub,
  so a working-tree edit never becomes its live hook. Open: the managed
  host, where the managed sandbox stays on in the center and limiting
  `center` to platform roots is undecided; `~/nixos-config` as a platform
  root without a devenv. The broker's stage B it also named (item 8) was
  dropped on 2026-10-24; proposals stay the CLAUDE.md contract and the
  center's permission prompt (`docs/sessions.md` section 4). What the
  command center is and does: `docs/command-center.md`. Added 2026-10-27:
  item 11 drops `harness.role` and the center; this gap is closed by it.

## Next, in order

0. **Audit follow-ups (2026-10-21).** What the audit fixes left open or
   turned up. The human's, in this order:
   1. Review and commit the staged set (17 files). One choice inside it:
      `~/.config/gh` in `denyRead` (`lib/settings.nix`) ends `gh` reads
      in sessions as well as the token leak; drop that line to keep them,
      and accept that `gh auth login` without a keyring puts a push token
      in reach again.
   2. Done 2026-10-21: `devenv/devenv.nix` imports `pkgs/direnv.nix`.
   3. Done 2026-10-24: `root_steps` in `pkgs/aj/bootstrap.sh` keeps
      only the nix.conf block and `userns_steps`; the dnf loop, the SELinux
      block, the daemon-socket block and `ROOT_RPMS` are gone, `reset` and
      `doctor` unchanged, bootstrap-test case 11 a doctor-only Fedora host
      line (changelog). As written: `scripts/install.sh` owns every root
      and pre-Nix step, `aj bootstrap` the user side.
   4. Done 2026-10-22: `CLAUDE.md`, section "Checks", carries the copy of
      the regular files and `nix flake check path:<dir>` (changelog). No
      memory note: `CLAUDE.md` is loaded into every session here.
   5. Done 2026-10-22: `tests/aj-bootstrap-test.sh` runs the jailer
      with the stub directory as the whole PATH (the wrapper prepends its
      own store tools), so a by-hand run no longer sees the host's
      `getenforce` and `code`; the header no longer claims the Nix build
      sandbox guarantees that. On a nix-installer host the bootstrap's
      `nix_path` then put the default profile's real nix ahead of the stub
      (52 cases, GitHub unreachable from a session): the profile.d files
      it sources are `AI_JAILER_NIX_PROFILE_D`, empty in the test.
   6. Done 2026-10-24: `aj init` counts a `devenv.lock` that exists
      before the first `direnv allow` as foreign and prints the inputs it
      pins under the `==>` header, so the y/N covers it; aj-init-test
      has the case (changelog). As written: a foreign lock was approved by
      the second `direnv allow` without being shown, and it pins every
      input, nixpkgs included.
   7. Done 2026-10-21: hook refuses `git checkout <ref> <path>...` (changelog).
   8. Run live 2026-10-29 as `w-acme` in `acme/infra`: the sandbox
      answers `wc: /home/w-acme/.git-credentials: Permission denied`,
      exit 1, neither `0` nor no-such-file; the case's pattern already
      accepts it (changelog). Written 2026-10-24: `aj check` case 14
      (`cred-sandbox`), the sandbox hiding `~/.git-credentials` on its
      own, by `wc -c ~/.git-cred*` with a fake file when the host has
      none; which of `0` or no-such-file the sandbox answers is for the
      first run to say (changelog). As written: the command spells the
      path around the hook's `cred_files` regex, create the fake line
      first when absent (`https://x:live-check@example.invalid`), remove
      it after, leave a real one alone.
   9. Done 2026-10-22, on the Ubuntu laptop itself: `aj upgrade`
      removed the scrub key from `~/.claude/settings.json`, the hook's
      preamble got devenv a writable runtime directory (changelog), and
      `aj check` passed 12 of 12: case 2 the devenv shell inside the
      sandbox, case 12 the two GitHub tokens.
   10. Confirm on the WSL host that `/model` in a session writes a plain
       `~/.claude/settings.json` after `aj bootstrap`. The staged set
       this item first named was committed (9197010), the WSL route then
       moved to `bilibo/nixos-wsl` (8e38390), its flake has no `harness`
       input, and its `check-access.sh` already checks for a plain file.
   Not planned: `~/.kube/config` and `~/.docker/config.json` the same way
   as `~/.aws`, until an ai-jailer host holds them.
1. **Interactive check of the repo-only shape.** `-p` sessions are verified
   (live-check 10/10 on 2026-10-20; `aj check` 12 of 12 on the Ubuntu
   laptop, 2026-10-22).
   Left: an `ajmux` session in the test repo, the trust dialog accepted
   once, hooks seen firing and the tmux window turning orange (`ajmux` on
   the checkout runs on the Ubuntu laptop since 2026-10-22; the orange
   window is observed on 2026-10-29 from a `claude -p` inside tmux, once
   the current window's tab got `window-status-current-style` too and
   `Stop` called the hook, and `aj check` case 20 runs that from now on;
   left is seeing it once from the `ajmux` TUI itself). The Notification
   matcher names are verified against the hooks reference; whether
   those events fire in tmux is not.
2. **Sandbox hardening**, the rest of the 2026-10-20 audit (runbook
   section 8, "Sandbox limits"); the strict allowlist, the literal
   `denyWrite` paths and the environment scrub are done. Each item is a
   `lib/settings.nix` change with a `project-settings-test` check, or a
   bootstrap change, plus a `live-check` case where the behaviour is only
   visible live:
   1. Read fence, prototyped live in the test repo on 2026-10-21 and kept
      opt-in: `ai-jail.readFence = true` gives `denyRead ["~/"]` plus
      `allowRead` for the repo and the shell-entry paths (`lib/settings.nix`),
      `ai-jail.extraAllowRead` for what the project reads under `$HOME`.
      Left: turn it on in a real repo and watch what breaks (a `path:`
      devenv input and `~/.cargo` are the known cases), then decide the
      default; `aj check` runs case 13 in a fenced repo.
   2. `permissions.blockReadsOutsideWorkingDirectories = true` last. Any
      scope, `true` wins; it stops the Read tool outside the working
      directories, which also stops a session in the test repo reading the
      ai-jailer checkout. Decide per role; the center must not set it.
   3. Keyring agent sockets: `denyRead` for `/run/user/*/gcr` and
      `/run/user/*/keyring` next to the `/run/WSL` entry. Every unix socket
      is reachable and the gcr address is guessable; `ssh-add -l` against it
      listed the user's keys from inside the sandbox (changelog 2026-10-21);
      whether the agent signs without a desktop prompt was not measured. If
      the wildcard does not take on Linux, the NixOS module writes the
      literal uid path. `aj check`: `ls /run/user/$(id -u)/gcr` fails
      and `ssh-add -l` against the guessed path gets `Could not open a
      connection`. `aj doctor`: warn when `ssh-add -l` lists a key that
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
      `devenv.lock` is the doubtful one. `aj check`: an interpreter
      write gets a permission error, not the hook's message.
   6. Answered 2026-10-24, no hole: in a session in this checkout `git
      config core.hooksPath` fails with `could not lock config file
      .git/config: File exists` (the sandbox masks `.git/config.lock` as
      `/dev/null`); `aj check` case 15 asserts it, not yet run by
      `aj check` itself, and runbook section 8 names the `-c`,
      `--global` and worktree forms as the accepted gaps (changelog). As
      written: `git config core.hooksPath /tmp/h` inside the sandbox,
      expecting a permission error on `.git/config`. Run by `aj check`
      live 2026-10-29 as `w-acme`: `could not lock config file
      .git/config: File exists`, exit 255.
   7. Done 2026-10-29 (changelog): this checkout's `.envrc` carries the
      template's refusal lines, and `aj check` case 19 (`devenv-local`)
      places a `devenv.local.yaml` from outside the session and expects
      the next command's preamble to show the `.envrc`'s line; the file
      is the script's, not an interpreter write's, since a cell need not
      have an interpreter and the hook never sees that write anyway.
      Skipped in a repo that keeps its own `.envrc`. Run by hand live the
      same day as `w-acme` in `acme/infra`: the hook answered `direnv
      export failed in ...: error: devenv.local.yaml is refused in a jail
      (...) (fix: remove the devenv.local file from your own terminal; it
      is not the agent's to remove)`, and after the removal the next
      session's command ran.
      Done 2026-10-26 for new repos (changelog): the template `.envrc`
      fails the load while either file exists; this checkout's own
      `.envrc` and the `aj check` case were still to do. As written:
      `devenv.local.nix` and `devenv.local.yaml` can be created by an
      interpreter write the hook does not see, and devenv imports them on
      the next evaluation without a `direnv allow` (the literal `denyWrite`
      that closed this broke the shell, 2026-10-22). Candidate: the `.envrc`
      the template writes fails the load when either file exists (a test
      before `use devenv`), so a jail never carries them; the
      checkout's own `.envrc` the same, by hand. `aj check`: a
      `python3` write creating one gets the next command's preamble failing
      loudly, not a silently imported file.
   8. **The tmux socket** (2026-10-24; work it before 2.1: the one open
      item that leaves the sandbox entirely). 2026-10-26: (a) written as
      hook rule 7 with hook-test cases and `aj check` case 16, both
      not yet run live (changelog); (b) open. 2026-10-29: case 16 ran
      live as `w-acme`, the hook refused `tmux new-window` with rule 7's
      message; `tmux display-message -p` is still unobserved (the check
      skips it outside tmux). `allowAllUnixSockets`
      reaches the user's tmux server, which runs outside the sandbox as
      the user: a sandboxed `tmux send-keys`, `run-shell` or `new-window`
      runs a command with no sandbox and no hook, or types a prompt into
      another session's pane. The hook has no tmux rule (synthetic run
      2026-10-24: `run-shell`, `new-window`, `capture-pane` pass). Not
      observed live: no server ran during the check (`tmux ls` in the
      sandbox: `couldn't create directory /run/user/1000/tmux-1000
      (Read-only file system)`, the directory absent); under `ajmux` the
      client takes the path from `$TMUX`, and a socket on the read-only
      `/run/user` mount answers (the gcr case, 2026-10-21). `ajmux` from
      a command-center session uses this path by design. Since 2026-10-24 the command center runs without the
      sandbox (`harness.role = "center"`), so it has nothing to escape and
      is out of this item's scope, and its `ajmux` launches cross no
      sandbox boundary. The item stays open for work repos, and the
      center's pane is among those a work session's sandboxed `tmux
      send-keys` can type into, which matters more now that the center
      has no sandbox. The `ajmux` flag hole is closed (2026-10-24): rule 6
      matches `ajmux` as well as `claude` (for `ajmux` outside the
      enforcement roots too) and reads separators inside quotes as text,
      with hook-test cases; the tmux rule of (a) stays open, a separate
      decision. Shapes:
      a. Hook rule: refuse `tmux` unless the subcommand is read-only
         (`ls`, `list-*`, `has-session`, `display-message -p`, `show-*`)
         and the command has no `-C`, `\;` or `source-file`; an allowlist
         because tmux takes unique prefixes (`neww`, `send`, `run`) and
         the executing set is long (`send-keys`, `paste-buffer`,
         `run-shell`, `new-window`, `split-window`, `new-session`,
         `respawn-*`, `pipe-pane`, `if-shell`, `source-file`, `set-hook`,
         `bind-key`, `display-popup`, `display-menu`, `command-prompt`,
         `confirm-before`, `set-option default-command`). Keeps `ajmux`; text only, so a script or
         `python` on the socket still gets through.
      b. Private socket: `ajmux` runs tmux with `-S` under a directory the
         repo file can `denyRead` without knowing the uid
         (`~/.local/state/ai-jailer/tmux`). The real boundary.
         Costs `ajmux` from inside a sandboxed work session (moot for the
         center, which has no sandbox) unless that repo lists it in
         `sandbox.excludedCommands` (unsandboxed, behind a prompt; verify
         with `allowUnsandboxedCommands = false` and for compound
         commands). A `claude` in the user's own tmux still
         uses the default socket (`/tmp/tmux-<uid>`,
         `$XDG_RUNTIME_DIR/tmux-<uid>`): needs the uid, or a glob
         `denyRead` that holds on Linux (verify).
      c. Claude outside tmux: `tmux-notify.sh` goes quiet (no orange
         window), the session layout is lost, and VS Code's terminal
         brings its own sockets into `/run/user/<uid>`
         (`vscode-ipc-*.sock`, seen 2026-10-24). Not on its own.
      First (a), with hook-test cases: one regex and its tests, `ajmux`
      keeps working. Then
      (b) together with 2.3 (the same mechanism, a socket directory in
      `denyRead`). `tmux-notify.sh` must keep working: it runs as a hook,
      outside the sandbox, needs `$TMUX` and `$TMUX_PANE` in claude's
      environment and the socket reachable from there, and only runs
      `set-window-option -t $TMUX_PANE window-status-style` (and `-u`).
      (a) does not touch hooks; (b) must leave `TMUX`/`TMUX_PANE` out of
      `credentials.envVars` unless that list is shown not to reach hook
      environments. `aj check`: from an `ajmux` session, `tmux
      display-message -p '#S'` prints the session name today; after (a)
      the hook refuses `tmux new-window`; after (b) the client cannot
      connect.
      Added 2026-10-27 (item 11): with one Linux user per org the
      tmux socket is per UID, so a worker's session reaches only its own
      worker's server; that server still runs unsandboxed as the worker,
      so (b) stays open.
   9. **Memory carve-out to the session's own project** (2026-10-24).
      Done 2026-10-26 (changelog); open: whether a worktree session's
      `CLAUDE_PROJECT_DIR` is the worktree path, which the rule refuses.
      As written:
      `env-guard.sh` allows `~/.claude/projects/*/memory/*`: a command-
      center session can write a work repo's memory (prompted, outside
      the working directory), and that repo's next session loads it with
      its own flag off. Restrict the case to the slug of
      `$CLAUDE_PROJECT_DIR` (verify Claude Code's slug rule and the
      worktree case); hook-test: another slug's `MEMORY.md` is refused.
3. **devenv-base repo with the `azure` module**: `az` pin, Terraform with
   azurerm/azuread/alz providers, tflint, trivy, and the `AZURE_CONFIG_DIR`
   task under `.git/devenv-base/azure` shared by worktrees.
   `imports: - devenv-base/azure` resolves to `azure/devenv.nix`, same rule
   as `ai-jailer/devenv`.
4. **Repo template**: the test repo minus Rust, plus the azure module;
   `aj init` renders it. Convert one real org repo; confirm
   `az account show` and `terraform plan` inside the sandbox with the
   network allowlist, and record the exact blob hosts the first
   `terraform init` and `trivy` run need.
5. **Reader-only service principal per org.** The one control that
   holds against every client, including things the hook never sees. Human
   logs it into the repo's `AZURE_CONFIG_DIR`.
6. **Limits suite**: `aj check` (`pkgs/aj/check.sh`) is the first cut. Still to do:
   a throwaway repo (`aj init` into a temporary code root), the cases
   from item 2, the `.devenv/shell-*.sh` litter count over 50 commands,
   `aj doctor --full` running it.
7. **Managed host base config**: a NixOS-WSL base configuration (and later
   a native NixOS one) shipped with the jailer, `ai-jail.enable` on both
   modules and nothing else, with the WSL-specific checks (`/run/WSL` and
   `/mnt/c` empty inside the sandbox, `cmd.exe` fails). First time the
   managed layer runs live. 2026-10-23: the module evaluates in `nix
   flake check` (`nixos-module-eval`, `nixos-module-assertion`) and
   `examples/nixos-host.nix` is the import snippet; no generation has been
   activated anywhere. 2026-10-24: the managed layer ran live on the
   NixOS-WSL laptop from 2026-10-23 (generation 8) and was then taken off
   it: the Windows route's host is plain by default
   (`examples/nixos-wsl-plain.nix`, the sandbox prerequisites and nothing
   from the jailer), the jailer comes afterwards as the user, and the
   managed base config stays as the stricter opt-in
   (`examples/nixos-wsl-host.nix`). 2026-10-26: `examples/` removed; the
   WSL shapes live in `bilibo/nixos-wsl`, and the README's managed-host
   row carries the import lines. What remains here is the native NixOS
   managed host, when someone wants one. 2026-10-27, item 12: the module
   is gone; `aj bootstrap` is the route on NixOS as everywhere.
8. **Broker mod: dropped 2026-10-24.** A mod is a hooks module the engine
   loads into every session on the machine, outside the Bash sandbox, and
   an enabled organisation mod is the one kind the built-in guard lets
   through; shipping the broker would have made its code, build,
   marketplace and registration keys a trust surface the jailer defends
   on every host, for coordination that never relaxes a rule. Removed the
   same day: `mods/` (the observe slice), `lib/mods.nix`, `harness.mods`,
   the managed marketplace directory with its
   `extraKnownMarketplaces`/`enabledPlugins` wiring, `packages.managed-mods`
   and `packages.harness-broker`, `tests/mod-validate-test.sh`. Kept: the
   policy that refuses mods on a managed host (`allowManagedModsOnly`,
   `strictKnownMarketplaces` empty unless `harness.extraKnownMarketplaces`
   lists a source, `disableSideloadFlags`, `allowManagedHooksOnly`),
   asserted by `managed-tree-test` and `nixos-module-eval`; the bootstrap
   turns account-synced skills and plugins off by default. Coordination
   stays the proposal flow (`docs/sessions.md` section 4) plus `ajmux`; a
   proposal record or a structural gate comes back only through a new
   dated entry here.

9. **Left open by the tier handoff** (`docs/handoff-tiers.md`, removed
   2026-10-26; the full phases: `git show 8e38390:docs/handoff-tiers.md`).
   - Done 2026-10-26 (changelog): `aj doctor` reports
     `AI_JAILER_CODE_ROOT`, `AI_JAIL_PROJECT` and the cwd's `AI_JAILER_ROLE`;
     the runbook's verification section starts with it.
   - A center on a managed host: a managed `sandbox.enabled = true` wins
     over the repo file, so `center` turns nothing off there. Undecided
     whether a managed host has a center at all. Closed by item 11
     (2026-10-27): there is no center.
   - Platform roots without a jail devenv (`~/nixos-config`): no role,
     no generated file; the planned `ajmux --settings` route was not built.
   - Org module (`imports: - ai-jailer/devenv/org`, with items 3
     to 5): `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`, `ORG_NAME`;
     `AZURE_CONFIG_DIR` per actor under `.git/devenv-base/`; a human-only
     `az-login` script; an `enterShell` tenant check; a hook branch that
     refuses `az`, `terraform apply|destroy` and `pulumi up` on a tenant or
     subscription mismatch; `allowWrite` and `lang` options.
   - `aj init` additions: an org registry
     (`~/code/git/<org>/org.toml`), the org block in
     `devenv.nix`, `README.md` and `.editorconfig`, the first commit, the
     template version in `devenv.yaml`, and `aj upgrade` showing the
     diff.
   - Limits-suite cases for item 6: nested `claude --add-dir ..`, `nh os
     switch`, `nixos-rebuild switch`, `home-manager switch`, reads of a
     sibling org file, outside the code root and of another project's
     `~/.claude/projects/`, `terraform apply` with `allowWrite = false` and
     with a mismatched subscription, a write to `~/.claude/settings.json`,
     `/mnt/c` and `/run/WSL` on WSL, `git push`.
   - Decisions for the owner: whether the work host carries the
     working-style rule from nixos-config; platform-tier cloud tools (`az`,
     `azd`, `terraform` into a devenv, or a PATH filter); whether
     `~/nixos-config` sessions may commit; where the doc-quality skills
     live for org repos (since 2026-10-24 ai-jailer ships no
     plugins); what `allowWrite = true` means against the unconditional
     apply/destroy deny; pointing `azfn-rust-handler/devenv.yaml` at this
     repo.

10. **Role design reviewed and kept (2026-10-26).** A proposal to drop
    `harness.role` for a sandboxed checkout with write rights under the
    code root and one option-fed hook was discussed and set aside by the
    owner the same night; the design stands. Three trims from that
    review, each standing on its own:
    - The tree and CLAUDE.md disagree: no commit sets `harness.role =
      "center"` here and `devenv.yaml` imports `./devenv`, so the
      checkout runs as a work repo with a hook built from the working
      tree (`AI_JAILER_ROLE=work` in its shell). Either set the role and pin
      the module as CLAUDE.md describes, or correct CLAUDE.md. Both files
      are the human's.
    - `aj check` reads the role from the repo shell and
      `.sandbox.enabled` from the settings file (`check.sh:127-132`) and
      warns when they disagree; the settings file is the truth, so drop
      the role lookup and the role half of `check-parser-test`.
    - `aj init` writes `# role = "center";` commented into every work
      repo's `devenv.nix`; only this checkout can ever set it, so stop.

11. **Worker users and managed-only rules (2026-10-27).** Reopens item
    10 ("Role design reviewed and kept, 2026-10-26"): the owner
    verified that `aj bootstrap` then `aj init` on a fresh
    host ends with a repo that enforces nothing, and a review of the
    tree at `ce6bd9f` found why (changelog 2026-10-27). Item 10's three
    trims are overtaken: the role, the lookup and the template line are
    gone. Decisions, the owner's:
    - Hard rules live in the host-wide managed tree (`/etc/claude-code`,
      root-owned), on every host shape; the owner's sessions are bound
      too. The repo file carries the project layer only, no hooks.
    - One Linux user per org from `harness.workers` in the NixOS
      module: `w-<org>`, 0750 home, group `w-<org>` with the
      owner as member, marker group `agents`, linger, never in
      `trusted-users`, Home Manager per worker, user settings seeded
      once, never a store symlink. `ajmux <org>/<repo>` hands over
      with `sudo -u w-<org> -i`.
    - The host matrix stays; `aj bootstrap` mirrors the module on
      Fedora and Ubuntu (`--workers`, `--owner`, `--owner-sudo`).
    - Claude Code's own sandbox stays; every `strictAllowlist` piece and
      the egress-filter idea are dropped; `allowedDomains` stays as a
      prompt-avoiding list.
    - Dropped: `harness.role`, `hooks/center-guard.sh`,
      `enforcementRoots`, the universal/project deny split,
      `AI_JAILER_ROLE`, `packages.managed-scoped`,
      `packages.project-settings-center`, the center and scoped checks,
      `docs/command-center.md`, bootstrap's user-scope settings block
      and `--account-sync`.
    - The sudo rule is owner to workers only (`<owner> ALL=(%agents)
      NOPASSWD: ALL`), never a rule with `%agents` as the user list.
    - Accepted costs: the owner's sessions lose the unsandboxed center
      (`gh`, `~/.ssh` and pushes from a session stop working);
      `syncClaudeAiSkills = false` in managed settings binds the owner's
      account too.

    Staged, not committed: the managed/repo split in `lib/`, hook
    scoping removed, the NixOS module's `owner`, `workers`,
    `ownerSudo` and `devenvCache`, the home module's settings seed,
    ajmux handover, `aj init`, `check` (18 cases) and `bootstrap`
    with the root steps, and the tests (changelog 2026-10-27 has the
    list and the results). Open:
    - [x] V1 managed sandbox in a worker session with no repo file:
      `claude -p 'grep -i nonewprivs /proc/self/status'` from a bare
      directory shows `NoNewPrivs: 1`, and `--debug-file` names the
      managed hook. Decides whether the 2026-10-27 failure is moot.
      Passed 2026-10-29 evening: as `w-acme` in a `mktemp -d`,
      `NoNewPrivs: 1`. The sandbox comes from the jail in the user scope
      (item 13 took `enabled` out of the managed body), so a worker is
      sandboxed everywhere. Moot.
    - [x] V2 project-scope `allowedDomains` under a managed sandbox:
      merged, ignored or prompting. Decides whether
      `ai-jail.extraAllowedDomains` stays in the devenv module or
      becomes host-wide only. Merged, 2026-10-29 evening: with
      `extraAllowedDomains = [ "dev.azure.com" ]` in `acme/infra`'s
      `devenv.nix`, the generated repo settings carried it and the
      sandbox proxy tunnelled `dev.azure.com` (`200 Connection
      Established`) while `example.org` got `deny network-outbound
      example.org:443 (user denied)`, no prompt under `-p`.
      `ai-jail.extraAllowedDomains` stays in the devenv module.
    - [x] V3 `allowedDomains = ["*"]`: open network or a literal host.
      Decides whether a no-prompt network setting exists. Open network,
      2026-10-29 evening: `extraAllowedDomains = [ "*" ]` tunnelled
      `example.org` with no prompt. It exists, and it is the cell's own
      choice in `devenv.nix`.
    - [x] V4 owner watching a worker: `sudo -u w-x -i tmux attach`
      against tmux `server-access` on a group-readable `-S` socket.
      Decides how the owner attaches. By becoming the worker, 2026-10-29
      evening: `sudo -u w-acme -i tmux attach -t acme-infra` from the
      owner's shell shows the pane `ajmux acme/infra` opened;
      `/tmp/tmux-1001` is 0700 `w-acme`, so no shared `-S` socket and no
      `server-access`.
    - [x] V5 `XDG_RUNTIME_DIR` under `sudo -u w-x -i` with linger:
      devenv, direnv and `tmux-notify.sh` work when ajmux exports
      `/run/user/$(id -u)`. Decides whether that export is enough.
      Enough, 2026-10-29 evening: the pane's `/proc/<pid>/environ`
      carries `XDG_RUNTIME_DIR=/run/user/1001`, the directory exists
      with linger, no `DIRENV_*` in the pane. The tmux session
      environment does not list it (not an `update-environment` name),
      which is fine.
    - [x] V6 Home Manager seed: `~/.claude/settings.json` is a plain
      0600 file after activation, `/model` rewrites it, a second
      activation leaves it; also whether Claude Code needs the file when
      absent, whether `harnessSeedClaudeSettings` after `linkGeneration`
      removes an older generation's store symlink first (suspected, not
      verified), and whether `home.stateVersion` accepts "26.05". The
      git identity form is settled (2026-10-27, later that day): the
      module's worker branch uses `programs.git.settings.user`, the form
      the host's home-manager (nix-community at 6d9655f) takes. Moot,
      2026-10-29: no home-manager ownership of these files (decided
      2026-10-28); `aj bootstrap` writes the jail into the worker's plain
      0600 file, and Claude Code rewrites that file for `/model` and the
      mode switch (item 14, 2026-10-29 evening).
    - [x] V7 group reads: the owner reads `/home/w-x/code/...`; `w-x`
      cannot list `/home/<owner>` or another worker's home. Passed
      2026-10-29 evening: the owner lists `acme/infra`; `w-acme` gets
      permission denied on `/home/nixos` and `/home/w-globex`.
    - [x] V8 a baseline `aj check` transcript in a worker repo. Item
      14's V13 run, 2026-10-29: `17 passed, 0 failed, 1 skipped`.
    - [x] V9 managed `syncClaudeAiSkills = false` honoured. As far as
      observable, 2026-10-29 evening: `--debug-file` logs skills loaded
      from the managed, user and project paths only, no sync line, and
      no `~/.claude/skills`.
    - [ ] Human steps: apply the two patches `c1-devenv-module.patch`
      and `f1-claude-md.patch` from the session scratchpad (the hook
      refuses those files; until the first is applied this checkout's
      shell does not evaluate), commit, rebuild the host with
      `harness.owner` and `harness.workers`, run `aj check` as a
      worker.
    - [ ] Untested: `nix build --out-link /etc/claude-code` as root
      through the daemon; the whole `home-manager.users.<w>` branch
      (Home Manager is not an input of this flake).
    - [ ] Follow-ups: `check_env`'s `fix: direnv allow <dir>` advice now
      names a command the hook refuses; place `extraAllowedDomains`
      after V2; the `grep 'direnv allow'` false positive; a `aj
      check` case for the direnv rule; the home module's
      `home.sessionVariables` (`AI_JAILER_CODE_ROOT`) reach a worker's
      shell only where something sources Home Manager's session file,
      which a host without `programs.bash` under Home Manager does not
      (found 2026-10-27 reading the sources while wiring the NixOS-WSL
      host, not live): either the home module enables `programs.bash`
      for workers, or the NixOS module exports the variable system-wide
      per worker; the host sets the worker's `codeRoot` to its
      system-level value meanwhile. Superseded 2026-10-27 by item 12:
      both modules are gone.

12. **One route on every Linux, run from the checkout (2026-10-27).**
    Reopens item 11's "one Linux user per org from
    `harness.workers` in the NixOS module" and "Home Manager per
    worker": the owner found that the NixOS route put jailer users,
    rules and options into the host repo (`bilibo/nixos-wsl`), which
    must stay usable on non-WSL NixOS and carry nothing of ai-jailer.
    Decisions, the owner's:
    - The ai-jailer checkout is the control point. Its checkout's devenv
      shell carries the `aj` CLI built from the checkout and sets
      `AI_JAILER_REF=path:<checkout>`; `aj bootstrap --workers ...`
      from that shell builds the Unix user and group model and links
      the managed tree on every Linux: Fedora 44+, Ubuntu, other
      Linux, NixOS and NixOS-WSL. `scripts/install.sh` stays the
      pre-Nix step for hosts without Nix.
    - NixOS runs the root steps like every host, with the differences
      bootstrap can live with: `nix.conf` and the sysctls are printed
      as options (store symlinks); no sudo rule (`/etc/sudoers` has no
      `@includedir`; the owner's own sudo serves, password or not,
      `--owner-sudo` ignored with a note); users from `useradd`
      (`users.mutableUsers`, the default; doctor reports a worker the
      receipt names but the host lacks). Checked 2026-10-27 on the
      NixOS-WSL host: setup-etc.pl removes only links into
      `/etc/static`, so the `/etc/claude-code` link survives rebuilds.
    - The NixOS module (`nixos/`) and the Home Manager module
      (`home/`) are dropped, with `nixos-module-eval` and
      `nixos-module-assertion`; three of their assertions moved to
      `managed-tree-test`. The host-wide options move to an optional,
      gitignored `host.nix` at the checkout root, merged by `flake.nix`
      into `packages.managed`; `packages.managed-wsl` is the `platform
      = "wsl"` variant, which bootstrap links under WSL;
      `managed-host-eval` checks both. A `github:` ref never carries
      `host.nix`; bootstrap warns when it finds one it cannot use.
    - Found while wiring it: a `path:` ref under the owner's 0700 home
      is unreadable to a worker, so `worker_user_steps` prefetches it
      into the store once (`nix flake prefetch --json`) and hands the
      workers that store path.
    - A host repo (`bilibo/nixos-wsl`) carries only `ajmux` and the
      tmux rules from this flake: no module, no CLI, no users.

    Open:
    - [x] V1 to V9 of item 11 stay as written, V6 narrowed to whether
      Claude Code needs `~/.claude/settings.json` at all (the seed that
      wrote it went with the home module). All nine closed 2026-10-29
      evening; the results are in item 11's boxes.
    - [ ] A worker's `aj init` writes the receipt's ref into the
      repo's `devenv.yaml`; after the prefetch that is a store path
      with no GC root (init warns). Options: a world-readable checkout
      location, or `github:` in worker repos' `devenv.yaml` (the hard
      rules come from `/etc/claude-code` either way).
    - [ ] `users.mutableUsers = false` removes the workers at the next
      rebuild; only doctor's receipt-versus-passwd line reports it.
    - [ ] `nix flake prefetch` on Fedora's packaged Nix, and `nix build
      --out-link /etc/claude-code` as root through the daemon: untested.
    - [ ] The first live run: `aj bootstrap --dry-run --workers
      test` from the checkout's shell on the NixOS-WSL host, then the
      real run as the gate for V1 to V9.

13. **The jailer runs unsandboxed; the sandbox is the workers'
    (2026-10-28).** Reopens item 11's "Claude Code's own sandbox stays"
    as it applied to the owner, and its accepted cost "the owner's
    sessions lose the unsandboxed center". Found the same day: a session
    in this checkout ran under the checkout's own project layer
    (`sandbox.enabled = true`, and no `allowAllUnixSockets`, which only
    the managed body sets), so no `nix` command reached the daemon and
    `nix flake check` could not run from a session at all. Decisions, the
    owner's:
    - The ai-jailer checkout is not sandboxed, before or after
      bootstrap. The deny rules, the hook and the mod policy still bind
      its sessions once the managed file exists.
    - The managed body no longer sets `sandbox.enabled`; it keeps
      `allowUnsandboxedCommands = false`, `failIfUnavailable` and every
      filesystem, credential and network list, which bind whichever
      scope turns the sandbox on. The owner's sessions run unsandboxed
      everywhere unless a repo file turns it on.
    - Each worker's `~/.claude/settings.json` carries `sandbox.enabled =
      true`, merged by `aj bootstrap` (recorded as a key; `reset` strips
      it). Managed `denyWrite ~/.claude` and the hook's user-config rule
      keep an agent from editing it.
    - A project or local file outranks the user scope, so the managed
      hook refuses every tool of a member of `agents` unless
      `sandbox.enabled` resolves to true over user, project, local and
      managed settings; a file that does not parse refuses too.
    - The repo layer writes `sandbox.enabled = true` or nothing, never
      false: `ai-jail.sandbox.enable = false` (default true) leaves the
      key out, so in a worker's repo the user scope still turns it on.
      This checkout sets it.
    - Handoffs from a session go to `proposals/` at the checkout root
      (gitignored), not the session scratchpad, which the owner cannot
      reach.

    Staged, not committed: `lib/settings.nix` (`enableSandbox`, managed
    body without `enabled`), the hook rule with 13 hook-test cases,
    bootstrap's worker key and doctor lines with 9 bootstrap-test
    cases, `managed-tree-test`, the `unsandboxed` mode of
    `project-settings-test` and its flake check. The module option and
    this checkout's setting are `proposals/2026-10-28-unsandboxed-checkout.patch`
    (the hook refuses both files). Open:
    - [ ] V10 (cut by item 14 on 2026-10-28: the lists left the managed
      body) a managed sandbox list (`denyRead`, `credentials.envVars`,
      `allowedDomains`) applies when only the user scope sets
      `sandbox.enabled`: a worker session's `cat ~/.git-credentials`
      gets no file and `echo $GH_TOKEN` prints nothing.
    - [ ] V11 (cut by item 14 on 2026-10-28) managed `failIfUnavailable =
      true` with `enabled` unset anywhere starts an owner session normally.
    - [x] V12 a worker session in a repo whose committed
      `.claude/settings.json` says `"enabled": false`: every tool
      refused with the hook's message. 2026-10-29, from the jailer
      session as `w-acme`, in a throwaway directory under the worker's
      home with only that file: `claude -p "run pwd"` got `env-guard:
      worker without a sandbox: enabled, allowUnsandboxedCommands and
      failIfUnavailable resolve to (false false true), not (true false
      true); the jail in ~/.claude/settings.json sets them and a project
      or local file must not change them`, exit 2, and the model stopped
      and named the project file. Item 13's live boxes are closed.
    - [ ] Not seen by the hook: `claude --settings <file>` at launch;
      `ajmux` never passes it, and rule 6 refuses it inside a session.
    - [ ] `aj check` as the owner: its `sandbox` case and the cases that
      need a sandbox are judged against a repo file that may now leave
      the key out.

14. **Law and jail: the jailer is bound by the law only; the jail is
    the prisoner's (2026-10-28).** Reopens item 11's "the owner's
    sessions are bound too; the rules are the host's, not a repo's" and
    its accepted costs, and supersedes item 13, which moved only the
    sandbox. The picture, the owner's: ai-jailer is the factory. `aj
    bootstrap` sets up the jailer's host: the law under
    `/etc/claude-code`, the prisoner users and groups, and each
    prisoner's chains. `aj init <org>/<repo>` builds a cell, the
    project layer of one repo. The owner works in a cell through `ajmux`
    as the prisoner; the AI minion is the escape risk, not the human.
    The shape comes first, so that what guides the tree away from it is
    cut; the rules grow on it afterwards. Decisions, the owner's:
    - The law binds everyone on the host, the jailer's sessions in this
      checkout included. Its content today: credential reads and `git
      push`. Credential reads as the hook's `cred_files` rule and
      `permissions.deny` `Read(...)` entries, since the sandbox lists
      (`denyRead`) bind only a sandboxed session and the jailer has none.
      More law is a dated entry here, one rule at a time.
    - Managed-only keys with no per-user form
      (`disableBypassPermissionsMode`, `allowManagedHooksOnly`, the mod
      policy, `syncClaudeAiSkills`/`Plugins = false`) stay in the managed
      file for now because nothing else can hold them; each is listed so
      it can be dropped on its own.
    - The jail is today's full ruleset: the deny rules, the hook's rules,
      the sandbox on with every filesystem, credential and network list
      and no unsandboxed fallback. It binds a member of `agents`
      everywhere, in a cell or outside one, so it lives on the user, not
      the repo: `aj bootstrap` writes it into each worker's
      `~/.claude/settings.json` in place of item 13's single key, `aj
      reset` strips it, and the managed tree carries the reference copy
      (`/etc/claude-code/jail-settings.json`).
    - The managed hook, run for everyone, is the gate. For everyone: the
      law rules. For a member of `agents`: the jail rules too, and before
      any tool the jail keys of the worker's user settings (under
      `CLAUDE_CONFIG_DIR` when set) compared to the reference, refusing
      when they differ, are missing or do not parse. Keys, not a file
      hash: `/model` rewrites the file. Item 13's resolution check for
      `sandbox.enabled` stays, since a project or local file outranks
      the user scope for a scalar. Rule 6 keeps refusing `--settings`,
      `--setting-sources`, `--bare` and gains `CLAUDE_CONFIG_DIR` on a
      nested launch.
    - The cell (`aj init`, the devenv module) carries allow rules, extra
      deny rules, extra hosts and the repo's own files as `denyWrite`,
      and never writes `sandbox.enabled`. This checkout keeps a project
      layer for its tools and gets no jail rule from it.
    - Cut: `ai-jail.sandbox.enable` and `enableSandbox` with
      `proposals/2026-10-28-unsandboxed-checkout.patch`; the hook's
      refusals of this checkout's `devenv.nix`, `devenv/devenv.nix`,
      `.envrc` and `.claude/` for the jailer, so `proposals/` is for
      prisoners' handoffs (`docs/sessions.md`), not the jailer's own
      files; item 11's accepted costs (`gh`, `~/.ssh`, pushes from the
      jailer's session, the account sync); `aj check` as the owner, it
      runs as a prisoner; V10 and V11 of item 13 (the lists leave the
      managed body). V12 stays.
    - Nothing is live: this host has no `/etc/claude-code`
      (2026-10-28), so no session here is bound by anything until
      bootstrap runs.

    Built the same day, by a session in this checkout, not committed:
    `lib/deny-rules.nix` returns `{ law; jail; }`; `lib/settings.nix`
    takes `body = "law" | "jail" | "repo"` (the `managed` flag,
    `enableSandbox` and the repo's `sandbox.enabled` are gone);
    `lib/managed-tree.nix` ships `managed-settings.json` (the law) and
    `jail-settings.json` (the jail) beside the hooks; the hook tells a
    worker from the jailer once by group, runs `jail_check` before a
    worker's every tool (the user file's keys against the reference, then
    `enabled`/`allowUnsandboxedCommands`/`failIfUnavailable` resolved over
    user, project, local and managed), applies the law to everyone (L1
    `git push`, L2 the credential files) and the rest to a worker only,
    with Edit and ConfigChange jail-only; `aj bootstrap` writes every
    top-level key of the jail into a worker's `~/.claude/settings.json`
    and records them, `aj reset` strips them, `aj doctor` compares the
    file to the reference; `aj check` warns on a repo file that says
    `enabled: false`; the devenv module, this checkout's `devenv.nix`,
    `aj init`'s contract, CLAUDE.md, the README's intro, layers and
    lockdown table, `docs/sessions.md` and the runbook say the new shape.
    The proposal patch is deleted. Decided while building, within the
    item's shape:
    - `host.nix`'s `extraDeny` and `extraAllowedDomains` go into the jail,
      `allowConnectors` too; `syncClaudeAiSkills`/`Plugins = false` move
      from the law to the jail (user scope honours a false), so the
      jailer's account syncs again. The law keeps only the managed-only
      keys: `disableBypassPermissionsMode`, `allowManagedHooksOnly`, the
      mod policy.
    - The law's credential rule names `~/.ssh/`, `~/.git-credentials`,
      `~/.config/gh/` and `~/.azure/` by text as well as the in-repo
      files: an unsandboxed jailer session has no `denyRead` to hide
      them. `ssh -i ~/.ssh/<key> host` passes (a use, not a read); `scp`
      of a key and `ssh host < key` are refused. `~/.aws` stays out.
    - The environment check (hook rule 8) runs for everyone: it is the
      devenv shell loading, not a restriction.
    - The jail check compares the reference's keys to the user file's
      values, not file hashes (`/model` rewrites the file), and reads the
      file under `CLAUDE_CONFIG_DIR` when set; rule 6 refuses
      `CLAUDE_CONFIG_DIR=` on a nested launch for a worker.
    Run by hand from this session against stand-ins for the store paths:
    hook-test 439 (every rule as a worker, the law section as the
    jailer), managed-tree 36, project-settings 17, aj-bootstrap 257 of
    280 with the same 23 failing on the committed tree under this
    session's sandbox (user namespaces read as missing, the home-manager
    cases need the stand-in in the store). Not run: the flake checks
    (`devenv-module-eval`, `managed-host-eval`, the rest; the daemon
    socket is refused in this session), statix, deadnix; nixfmt clean,
    shellcheck clean on bootstrap.

    Open:
    - [x] Whether `permissions.deny` `Read(...)` on the credential files
      stops the Read tool for an unsandboxed jailer as the reference says
      (the hook covers Bash; Edit and Write of those files rely on the
      Read deny, 2.1.228+). 2026-10-29, from the jailer session: yes
      inside the project directory (a Write of `<cwd>/probe.tfstate` was
      refused with "covered by a Read deny rule"), but a `**/` pattern is
      relative to the session's project directory: the same file under
      `/tmp` was written and read back by the tools, and only the hook's
      Bash rule caught `cat` on it. Absolute patterns (`~/.ssh/**`) are
      not affected.
    - [x] `nix flake check` on a copy of the regular files, 2026-10-28,
      from a session whose Bash sandbox had been turned off: every check
      passes (hook-test 443, hook-test-worktree 462, aj-bootstrap 280,
      aj-doctor 71, aj-init 82, check-parser 115, managed-tree 37,
      `managed-host-eval`, `devenv-module-eval`); statix and deadnix clean
      on the changed Nix files. The by-hand run's 23 bootstrap failures were
      that session's sandbox. Left: the human's review and commit.
    - [x] The first live run (item 12's gate), with V12 of item 13 and:
      V13 a worker session with the jail written starts and `aj check`
      passes as that worker; V14 a worker whose `~/.claude/settings.json`
      was edited (a deny rule removed) has every tool refused with the
      hook's `differs from` message, and `aj bootstrap` as that worker
      repairs it; V15 a jailer session in this checkout runs `nix flake
      check`, `git add` and `sudo -v` (prompted), and is refused `git
      commit`, `git push` and `cat ~/.ssh/id_ed25519`.
      2026-10-29: V15 passes as written (`nix flake check` 25 s on the
      checkout, `git add`, `sudo -v`; the three refusals each came back
      as `env-guard: git commit/push blocked` or `credential file access
      blocked`, and a compound command containing `git commit` was
      refused whole). V13: the worker session starts (SessionStart hook
      exit 0, init line, `permissionMode: default`), but `w-acme` has
      never logged in, so `aj check` ended `1 passed, 16 failed`, every
      one a `Not logged in · Please run /login` result; `aj check` now
      says that once (login pre-flight). Left for the human: `claude
      auth login` as `w-acme` (done the same day; `claude /login` on a
      first launch prompts twice), then `aj check` again. V14: not run; the
      session's permission classifier refuses editing a worker's
      settings, so the human runs it (the commands are in the V14 row
      of `docs/verified.md`).
      V13 second run, logged in: 9 passed, 8 failed, all eight
      `bwrap: execvp /bin/bash: No such file or directory`: the day's
      `Read(**/.devenv/**)` jail rule, merged by Claude Code into the
      sandbox's `denyRead` and expanded through `.devenv/profile` and
      `.devenv/bash-bash`, had put a tmpfs over the bash package `/bin/bash`
      points to on NixOS. Reverted; third run the same day: `aj check:
      17 passed, 0 failed, 1 skipped` (tmux-display, outside tmux). V13
      passes. V14, 2026-10-29 afternoon, the human's edit (`del
      (.permissions.deny[0])` as `w-acme`): the session answered that it
      cannot edit the file and named `aj bootstrap`; the hook on a plain
      `pwd` said `worker without a jail: ~/.claude/settings.json differs
      from /etc/claude-code/jail-settings.json at permissions (aj bootstrap
      rewrites it; a session must not edit it)`, exit 2; `aj doctor` as the
      worker: MISSING, same words. `aj bootstrap --no-root --yes` as the
      worker rewrote the jail; hook exit 0, doctor 0 missing, a session
      ran `pwd` again. V12 is item 13's, still open (passed 2026-10-29,
      item 13).
    - Found 2026-10-29 evening, during V4: the interactive claude in the
      `ajmux` session wrote `permissions.defaultMode: "auto"` (with
      `theme` and `tui`) into `w-acme`'s user file one minute in; the
      jail pinned `defaultMode: "default"`, the hook's `permissions`
      comparison failed, and every tool of the worker was refused with
      V14's message until `aj bootstrap --no-root --yes` as the worker.
      Decided the same evening (the owner's: what happens inside a cell
      is the worker's, as long as nothing gets out): the jail no longer
      carries `defaultMode`; the hook, bootstrap's write check and
      doctor compare `permissions` with that key removed on both sides,
      and bootstrap keeps the worker's value across the write. Two
      hook-test cases: a mode of the worker's own passes, an added
      `permissions.allow` is still refused. `disableBypassPermissionsMode`
      stays compared.
    - [x] `Read(**/.terraform/**)` in the jail: the same merge masks every
      match with a tmpfs, so a cell with `.terraform/providers` would lose
      them inside the sandbox and `terraform plan` could not load providers
      (found 2026-10-29, not yet seen in a cell: `acme/infra` has no
      `.terraform`). Decide: drop the rule (the hook's L2 blocks state
      writes already; a `denyWrite` on `.terraform` would keep the files
      safe without hiding them), or keep it until the first terraform cell
      shows the failure. Dropped, 2026-10-29 evening (the owner's): the
      state file inside that directory is still covered by
      `Read(**/*.tfstate)`, the hook's rule 2 blocks state writes, and the
      providers are not secret. `tests/managed-tree-test.sh` asserts the
      rule's absence from the law.
    - [x] Each managed-only key in the law, decided on its own: bypass
      mode off, `allowManagedHooksOnly`, the mod policy. All three bind
      the jailer today. Bypass mode off: kept and verified 2026-10-29
      evening (`docs/verified.md`): as `w-acme`,
      `--dangerously-skip-permissions` and `--permission-mode
      bypassPermissions` are downgraded silently under `-p`, the debug
      log says `bypassPermissions mode is disabled by settings`, the
      command ran sandboxed. The other two, from the docs the same
      evening (settings reference, hooks, plugins/security,
      plugins/org, plugins/mods/admin): `allowManagedHooksOnly` is
      binary; with it off, hooks from every scope and plugin merge and
      managed hooks still cannot be removed by a lower scope, so the key
      buys only "no extra hooks". That is the security half: hook
      commands run outside the sandbox with the user's full permissions
      and `permissions.deny` does not cover them, so an extra hook is an
      unsandboxed shell for whoever can write a settings file. Keep.
      The mod policy is three keys: `allowManagedModsOnly` restricts
      mods only (the JavaScript a plugin runs inside Claude Code), not
      skills, commands, agents, `hooks.json`, MCP or LSP servers;
      `strictKnownMarketplaces = []` is what blocks every plugin,
      the official marketplace included; `disableSideloadFlags` rejects
      `--plugin-dir`, `--plugin-url`, `--agents` and `--mcp-config`.
      Owner's wish: plugins yes, JavaScript no. Proposed: keep
      `allowManagedModsOnly` and `disableSideloadFlags`, list the
      marketplaces in `host.nix` (`extraKnownMarketplaces`). Decided
      2026-10-29 late evening (the owner's): all three keys stay in the
      law as they are. Plugins come later per host through
      `extraKnownMarketplaces` in `host.nix`; when that happens the law
      must also register the marketplace with Claude Code's own
      `extraKnownMarketplaces` key, since a machine that ran under `[]`
      never re-registers the official one by itself (parked, not for
      the release).
    - [x] Found in the same reading, 2026-10-29: MCP servers (stdio),
      LSP servers, monitors and hooks run outside the sandbox, and
      "permission rules and sandbox cover the tool calls Claude makes,
      not the code a plugin runs by itself". The law has no
      `allowedMcpServers`, `allowManagedMcpServersOnly` or
      `deniedMcpServers`, and a cell's `.mcp.json` is not in the
      protected paths, so a plugin's or a repo's MCP server is a way
      out of the sandbox for a worker today. Decide: `allowedMcpServers`
      in the law (empty, or the owner's remote servers) with
      `allowManagedMcpServersOnly`, and `.mcp.json` into
      `projectConfigPaths`; the owner's sessions are bound by the same
      law. Accepted as is, 2026-10-29 late evening (the owner's): no
      MCP restriction in the law; setting up an MCP server is a valid
      use of a cell and functionality is not limited for a risk nobody
      has hit. What stands between a model and an unsandboxed server
      today is Claude Code's own approval of a project `.mcp.json`
      (interactive prompt; a `-p` run needs prior approval), which the
      worker's human answers. Reopen with a dated line if a cell ever
      shows an unapproved server starting.

    Added to the law the same day (the owner's): `git commit`, for
    everyone, the jailer included. The host's `allowLocalCommits`
    (`host.nix`) lifts it from the law and the jail together, as it
    lifted the jail's alone before. The hook's L1 rule matches `commit`
    and `push` as git subcommands (`git commitlint` passes; `git
    commit-tree` stays a jail rule).

15. **The nixos-wsl `install-wsl.ps1` run from scratch (2026-10-29).**
    Left out of the release on purpose: `v0.1.0` (2026-10-29) is a tag
    on `main` with the README true, and `bilibo/nixos-wsl` has not been
    installed end to end by `install-wsl.ps1` since the rename
    (2026-10-28) and the one-route bootstrap (item 12). The human's, on
    a Windows machine without the distro: the script as the nixos-wsl
    README says, then from this checkout's shell `aj bootstrap
    --workers <a,b>`, `verify.sh`, `aj doctor` as the owner and as a
    worker, `aj init` and `aj check` as a worker. Each step that fails
    is a changelog line and a fix in whichever repo owns it; the result
    is a row in `docs/verified.md` behind the README's NixOS-WSL
    host-table line.

16. **Plugins per host (2026-10-29).** Decided 2026-10-29 late evening
    (item 14): plugins yes, JavaScript no, nothing for the release. The
    law keeps `allowManagedModsOnly`, `disableSideloadFlags` and
    `strictKnownMarketplaces`, which `host.nix`'s
    `extraKnownMarketplaces` fills and which is `[]` by default, the
    list that blocks every plugin today, the official marketplace
    included. When a host wants one, two halves, never one: the
    marketplaces listed in `host.nix` (the official one is `{ source =
    "github"; repo = "anthropics/claude-plugins-official"; }`), and the
    law registering each one with Claude Code's own
    `extraKnownMarketplaces` key, which the law does not write today
    (`managed-tree-test` asserts its absence), because a machine that
    once ran under `[]` never re-registers the official marketplace by
    itself. The test turns around then: the two keys carry the same
    list. Starts when the first cell needs a plugin; until then the
    empty list stands.

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
  the SessionStart-only variant is the fallback. 2026-10-22: the case for
  it is no longer cost alone. Five workarounds now exist for running
  direnv and devenv inside the sandbox (changelog, case 2), and the
  SessionStart hook runs outside it, so it could run `direnv export bash`
  once and write the exports into the env file; the cwd-change and
  file-change events would refresh it, if they fire as the hook assumes.
  Deciding it reopens decision 7.3 with a dated entry here. Measured
  2026-10-23 on the NixOS laptop in this checkout: `direnv export bash`
  0.19 to 0.23 s warm, 4.5 s after a change; the hook's `check_env` adds
  36 to 41 ms per Bash call in steady state (changelog).
- Account-synced skills and plugins: decided 2026-10-24 for unmanaged
  hosts, off by default (`aj bootstrap` writes `syncClaudeAiSkills`
  and `syncClaudeAiPlugins = false`; `--account-sync` opts back in,
  `--no-account-sync` is still accepted). The managed settings do not set
  them; whether the managed host should is still open.
- `LD_LIBRARY_PATH` inside a session carries a Nix alsa-lib path that
  neither devenv, direnv nor the jailer exports (2026-10-21); the host's
  `code` loads `librt` from the Nix glibc through it and dies. Trace the
  exporter (the launcher, the terminal, Claude Code itself) before the
  managed host, where more host binaries run from sessions. Traced
  2026-10-24 (changelog): nixpkgs' `claude-code` wrapper (`--prefix
  LD_LIBRARY_PATH : <alsa-lib>/lib`), inherited by every hook and Bash
  command. Closed the same day: `pkgs/claude-code.nix` drops the wrapper
  line and put alsa-lib on the binary's RUNPATH; the home module (gone
  2026-10-27, item 12), `packages.claude-code` and the devenv module use it; `claude-code-test`
  checks it (changelog). Not the hook preamble: that would have covered
  the Bash tool only. The RUNPATH went on 2026-10-27 (changelog): it
  segfaults claude-code 2.1.303, and it never reached the audio addon's
  own libasound dependency; the override now only removes the variable.

## Ideas, not planned

- `docs/suggestion.md` (2026-10-24): agents built on the Claude Agent SDK
  (ai-jailer's own jobs, headless agents on the managed host; three
  test cases before any code), and the agent's cloud identity (Entra
  Agent ID) as a separate repository with three seams into this one.
  Also (2026-10-28) staleness: a host never learns its rules are old;
  a one-line signal at the factory shell's entry when it bites.
- Tighten the hook with the gaps listed in the runbook's known-gaps section:
  gh and package publishing as project rules, git exec-vector config keys,
  az transfer verbs, and a fail-closed rule for dynamic shell constructs
  (`$IFS`, `$(`, `base64 -d |`). Each one
  starts as a test case. Also: stop matching `*/devenv.nix` when the path
  is ai-jailer's own `devenv/devenv.nix`, which the hook refuses today.
  Also: the `direnv allow|permit|grant|edit` rule (item 11) refuses a
  quoted mention (`grep 'direnv allow' docs/`).
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
  `ai-jail.allowRemoteControl` option in the `allowConnectors` shape, and
  the managed file makes it final. Which scope wins when they disagree is
  not stated; assume `true` wins as for `disableBypassPermissionsMode` and
  confirm live. Off until the verification suite exists (the broker it also
  waited for was dropped on 2026-10-24); the
  hook's nested-launch rule does not need the flag once the key is set.
- nix-darwin module: same `lib/`, managed settings under
  `/Library/Application Support/ClaudeCode/`, seatbelt sandbox keys; the
  glob `denyWrite` entries apply there.
- Container route: built and set aside in the claude-nix-harness-container
  repo (same `lib/`, root-owned store behind a nix-daemon, devcontainer
  files per engine; never run under podman or VS Code). The WSL tier does
  not use it; NixOS-WSL builds its distro tarball from the NixOS module
  (the NixOS module is gone since 2026-10-27, item 12; `bilibo/nixos-wsl`
  is its own flake).
- A parser-based second guard (cc-safety-net rulebooks) beside the regex
  hook.
- An assertion in `devenv/devenv.nix` that `ai-jail.settings` sets no
  `permissions.deny` and no list under `sandbox` (2026-10-24): merged
  with `recursiveUpdate`, either replaces ai-jailer's own list, and
  only `aj init`'s settings test notices, once. Today
  `docs/project-devenv.md` warns against it.
- Quiet Terraform and `az` in cells (2026-10-29; measure first): `env`
  in `devenv/devenv.nix` (`lib.mkIf cfg.enable`, `lib.mkDefault` per
  key: `TF_CLI_ARGS_plan = "-no-color -compact-warnings"`,
  `TF_CLI_ARGS_{validate,init,show} = "-no-color"`,
  `AZURE_CORE_ONLY_SHOW_ERRORS = "true"`, `AZURE_CORE_NO_COLOR =
  "true"`; never a global `TF_CLI_ARGS`, `-compact-warnings` breaks
  `init` and `workspace`; Terraform ignores `NO_COLOR`). The plumbing
  is there: the hook's `$CLAUDE_ENV_FILE` preamble runs `direnv export`
  before every Bash call. But the Bash tool has no TTY (`[ -t 1 ]` is
  false, checked 2026-10-29) and both tools drop colour without one, so
  the colour half is moot; what is left is `-compact-warnings` and the
  az preview and survey banners. Only after the first `terraform plan`
  or `az` run in a cell shows the noise in a transcript (`aj check`
  keeps them under the `transcripts:` directory it prints).
- Splitting `pkgs/aj/bootstrap.sh` (1,356 lines on 2026-10-29) into
  common, bootstrap, doctor and reset. It helps only factory sessions
  that edit doctor or reset, and the cut is not clean: `report()` is
  called by `doctor` and by `bootstrap|upgrade`, so it moves to common
  or doctor's part is in bootstrap's build too. If ever done: `usage()`
  reads its own file's header up to the first `# shellcheck` line, so
  the per-command header comes first in the merged text; `CMD` from
  `AI_JAILER_CMD` (`pkgs/aj.nix`) and the dispatch stay;
  `tests/aj-bootstrap-test.sh` and `tests/aj-doctor-test.sh` pass
  unchanged. Only if the file keeps growing.
