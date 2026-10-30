# Changelog

Dated entries, newest first. The roadmap says what is next; this says what
happened and what was learned on the day.

## 2026-10-29

- `ajmux` gives each terminal its own view: two VS Code tabs attached to
  one project followed each other, since a tmux session has one current
  window for all its clients. Now a terminal attaching a session another
  terminal shows gets a grouped session `<session>-<pid>` over the same
  windows, destroyed on detach, and the new window is opened with `-d`
  and selected for that terminal only; from inside tmux the calling
  terminal moves to the new window, or switches to the project's session
  or a fresh view. Learned on a private server: `destroy-unattached on`
  set on a session with no client destroys it at once, so it is set only
  after the attach or switch; option commands reject the `=name` target
  that `switch-client` takes; a bare `display-message` or `kill-window`
  acts on the session's current window, not the caller's (the test stubs
  now name their pane). Two `ajmux-test` cases cover the view; the
  inside-tmux paths were probed by hand (verified).
- The orange window showed nothing on the window being looked at: tmux
  draws the current window's tab with `window-status-current-style`
  alone whenever that option is not `default` (its `status-format[0]`),
  and on nixos-wsl it is `underscore`, so the colour the hook put in
  `window-status-style` appeared only after switching to another window.
  `tmux-notify.sh` now sets and unsets both styles; the rendered status
  line was checked on the live server (verified). Learned on the way: a
  by-hand call needs the word `waiting` (not `wait`) and a shell inside
  tmux, since the client finds the server through `TMUX`. The hook
  also runs on `Stop` now: the hooks reference puts `idle_prompt` about
  60 s after a turn ends and `permission_prompt` about 6 s into a prompt,
  so a session that had merely finished its turn coloured nothing; `Stop`
  does not fire on an interrupt, where `idle_prompt` still covers. Live
  after `aj upgrade`. The hook firing from a live session is observed
  the same evening: one `claude -p` with the pane's `TMUX` and
  `TMUX_PANE` left window 0 of `local-ai-jailer` with both styles set
  (verified); `aj check` case 20 (`tmux-notify`) does that run from the
  check's own window from now on, so the orange window is a line in
  the check, not a thing to watch for by hand. The debug log names no
  command hook, so the case reads the window options back.
- `v0.1.0` tagged on `main` at `ec2307d` and pushed, evening: the first
  release, a tag with the README true (the release definition decided
  the same day). The sprint's `docs/tasklist.md` is folded into the
  roadmap and deleted: 6.6 (quiet Terraform and `az`, measure first)
  and 6.7 (splitting `bootstrap.sh`) are under "Ideas, not planned";
  the `install-wsl.ps1` from-scratch run and plugins per host are
  items 15 and 16. Its history is this changelog and
  `docs/verified.md`; its standing routines are the runbook's section
  6 and the nixos-wsl README.
- Evening: V1 to V9 of roadmap item 11 closed live as `w-acme` (item 11
  has each result): a worker is sandboxed in a bare directory too (the
  jail's user scope), a cell's `extraAllowedDomains` is merged into the
  sandbox proxy's allowlist and `"*"` opens it, the owner attaches with
  `sudo -u w-acme -i tmux attach` (the socket dir is 0700, nothing
  shared), the pane carries `XDG_RUNTIME_DIR`, other homes are denied,
  no skill sync in the debug log.
- `Read(**/.terraform/**)` dropped from the deny rules (the owner's,
  evening): it would mask a cell's providers inside the sandbox, the
  state file in that directory is covered by `**/*.tfstate`, and the hook
  blocks state writes. `managed-tree-test` asserts the absence.
- Bypass mode verified off for a worker (debug log `bypassPermissions
  mode is disabled by settings`, the command still sandboxed); kept in
  the law.
- The three managed-only keys decided (the owner's, late evening): bypass
  mode off, `allowManagedHooksOnly` (hooks run outside the sandbox and
  deny rules do not cover them, so this is the wall against an extra
  hook) and the mod policy (`allowManagedModsOnly` is "no JavaScript";
  plugins come later per host through `extraKnownMarketplaces`) all
  stay. MCP and LSP servers run outside the sandbox and the law does
  not restrict them: accepted as is, a cell may need one; Claude Code's
  approval of a project `.mcp.json` is the human's gate.
- New `docs/verified.md`: one row per live check, with date, how and
  result, so README and runbook claims can point at evidence. Today's
  rows are in; the runbook's V1 to V9 table points there.
- Found during V4: a mode switch in the TUI writes
  `permissions.defaultMode` into the worker's user file; the jail pinned
  it and the hook locked the worker out (V14's message). The jail drops
  `defaultMode`; the hook, bootstrap and doctor leave that key out of
  the comparison and bootstrap keeps the worker's value. Two hook-test
  cases. The cell template's `extraAllowedDomains` comment no longer
  calls V2 pending. Applied live the same evening (`aj upgrade
  --no-profile --workers acme,globex`, 0 missing everywhere); `aj check`
  as `w-acme` afterwards: `18 passed, 0 failed, 1 skipped`.
- Roadmap 2.7 closed: this checkout's `.envrc` has the template's lines
  (the load fails while `devenv.local.nix` or `devenv.local.yaml`
  exists; `direnv allow` once after pulling, since the file changed), and
  `aj check` case 19 (`devenv-local`) places an empty `devenv.local.yaml`
  from the script, runs one command and expects the preamble's `is
  refused in a jail` line and no output from the command, then removes
  the file. The script places the file, not a session's interpreter
  write as the roadmap first said: the hook refuses a shell write that
  creates it, a cell need not carry python3, and the layer under test is
  the `.envrc` and the preamble either way. Skipped in a repo with its
  own `.envrc` or an existing `devenv.local.yaml`. Eighteen sessions,
  nineteen as a worker (README, runbook); parser test lists the case.
  Run by hand live as `w-acme` in `acme/infra`: refused with the
  `.envrc`'s line and the hook's fix text; the next command after the
  removal ran.
- Live, afternoon: V12 passes (a worker session in a directory whose
  `.claude/settings.json` says `sandbox.enabled: false` had `pwd`
  refused by the hook's `worker without a sandbox` line, exit 2), so
  item 13's live boxes are closed; V10 and V11 had gone with item 14.
  Read back from V13's transcripts: the sandbox answers
  `~/.git-credentials` with `Permission denied` on NixOS-WSL, not an
  empty file or no-such-file (roadmap 0.8); `git config
  core.hooksPath` stops at `could not lock config file .git/config`
  (2.6); the hook refused `tmux new-window` as rule 7 says (2.8a).
  Left on the gate: V4 and the three managed-only keys, both the
  human's; `verify.sh` says the host's ai-jailer lock lags.
- `customer` is `org` everywhere: `<org>/<repo>`, `w-<org>`, the
  `ajmux` usage and errors (`a worker cannot open another org's
  session`), `aj` help, bootstrap's text, the comments and the docs. The
  README defines an org once: whoever the work is for, a client, a team,
  an open-source org or yourself, with one Linux user per org as the
  boundary. Worker user names, the receipt's `root.workers` and
  `AI_JAIL_PROJECT` are unchanged. Decided 2026-10-28: no consulting
  speak; `project` already names the pair.
- Bare `aj upgrade` upgrades the workers recorded in the receipt
  (`root.workers`), as the README promised since 2026-10-28; a recorded
  worker the host lacks is created again, which is what doctor would
  ask for. Without `--owner-sudo` the existing sudo rule is left alone,
  because the receipt does not record it.
- Worker users get `/bin/bash`, or `/run/current-system/sw/bin/bash` on
  plain NixOS (only `/bin/sh` there), never `$(command -v bash)`: from
  the checkout's devenv shell that is a store path garbage collection
  would remove, and `sudo -u w-x -i` with it. Doctor's bwrap probe runs
  `true` off PATH instead of `/bin/true`.
- Bootstrap's store-ref warning says what is true: the owner's
  `aj upgrade --workers` does move a worker's snapshot, an upgrade the
  worker runs itself cannot. The closing "Next" text names only what the
  run wrote: no profile.d or `~/.bashrc.d` on NixOS, no log-out note on
  NixOS or with `--no-profile`.
- `aj check` makes one login pre-flight call before the cases. The first
  live run as `w-acme` ended `1 passed, 16 failed`, every FAIL a
  `no line matched` whose transcript carried `Not logged in · Please run
  /login`: a worker that has never logged in looked like sixteen
  regressions. Now one `FAIL  login` names the user and the fix, the
  cases do not run, exit 1. The parser test has a stub-claude case.
- `hooks/env-guard.sh` refusals say what to do instead: the git
  history/index, terraform and az write messages keep their prefix and
  append the alternative (`git add`, `git switch -c`, `git show
  HEAD:<path>` for git; plan/validate for terraform; read/list/show for
  az, the human runs the writes). A bare `blocked` made a model try flag
  variants for two or three turns.
- `aj init`'s CLAUDE.md contract is action rules, not plumbing: read
  `devenv.nix` first for tools and identifiers, never read dotenv,
  tfvars, tfstate, `.devenv/`, `.direnv/`; a change to the protected
  files goes to `proposals/<YYYY-MM-DD>-<topic>.patch`; stage only,
  revert with `git show HEAD:<f> > <f>`; scope `az` output; stop on a
  refusal. The paragraph on where the layers come from is gone, a
  worker never needed it. The template now gitignores `proposals/`
  (promised, not done) and writes `.ignore` with `devenv.lock`, so a
  ripgrep-backed Grep skips the tracked lockfile; the factory has the
  same `.ignore`, since `scripts/install.sh` runs `aj init` here.
- Tried and reverted the same day: `Read(**/.devenv/**)` and
  `Read(**/.direnv/**)` for the workers, to keep a model out of the
  evaluated profile and env dumps. Claude Code merges `Read(...)` deny
  rules into the sandbox's `denyRead` (its settings reference says so)
  and expands the glob through symlinked directories, so
  `.devenv/profile` and `.devenv/bash-bash` put an empty tmpfs over the
  devenv profile and the bash package in the store, and every sandboxed
  command died with `bwrap: execvp /bin/bash: No such file or directory`
  (V13's second run: 9 passed, 8 failed, the eight all this). Found
  with `strace -f -e trace=execve` around the worker's `claude -p`,
  which shows the bwrap mounts; `--debug-file` logs nothing of the
  sandbox, and `--settings` cannot swap `sandbox.bwrapPath` under the
  managed tree. The test now pins that the jail has no such rule and
  still pins `.terraform`. Open: `Read(**/.terraform/**)` will do the
  same to a cell's `.terraform/providers` once one exists (roadmap item
  14).
- CLAUDE.md's Checks: an unsandboxed session runs `nix flake check` on
  the checkout (25 s, exit 0 today); the tar copy is the sandboxed
  worker's fallback, `-L` only after a failure.
- Live, from the jailer session: V15 of the release gate passes; the
  `Read(...)` deny binds the unsandboxed jailer's Read and Write inside
  the project directory, and `**/` patterns stop at that directory (the
  roadmap has the detail). V13 waited on the worker's first login (`claude
  auth login`; `claude /login` on a first launch prompts twice, the
  onboarding sign-in and then the command) and on the `.devenv` revert
  above; its third run is `17 passed, 0 failed, 1 skipped`. V14, run by
  the human: a worker whose `~/.claude/settings.json` lost a deny rule
  had every tool refused (`worker without a jail: ... differs from
  /etc/claude-code/jail-settings.json at permissions`), doctor said the
  same, and `aj bootstrap --no-root --yes` as that worker rewrote the
  jail. Item 14's live-run box is closed; V12 (item 13) and the three
  managed-only keys stay open.

## 2026-10-28

- `aj bootstrap` on NixOS writes nothing the system configuration already
  provides. Seen on the first NixOS-WSL bootstrap (`programs.direnv`,
  `devenv` and `ajmux` in `environment.systemPackages`): the owner got a
  nix profile that shadowed the system's direnv and devenv, a
  `~/.bashrc.d` with a second direnv hook, a `~/.config/direnv/direnv.toml`
  that `DIRENV_CONFIG=/etc/direnv` hides, an `environment.d` PATH entry
  for a desktop WSL does not have, and `~/.config/Code/User/settings.json`,
  which Remote-WSL never reads (the remote's file is
  `~/.vscode-server/data/Machine/settings.json`). All of it came back at
  every `upgrade`, since the user steps skip only store symlinks. Now:
  direnv.toml is skipped when `DIRENV_CONFIG` points elsewhere, the rc
  files when the hook is in `/etc/bashrc` and the code root is the
  default, environment.d on NixOS always, the VS Code user settings under
  WSL always (the extension is still installed: from a VS Code terminal
  the Remote-WSL CLI puts it in the remote, which doctor's comment had
  wrong); doctor stops asking NixOS for an environment.d entry. The nix
  profile is still `--no-profile`'s to decline: bootstrap cannot tell a
  system package from a profile one by PATH alone, and a NixOS host
  without those packages needs the profile. Not moved into home-manager:
  the host's configuration keeps `~/.bashrc` the person's and `aj` in the
  checkout, and owning dead files there to placate the bootstrap would
  be the wrong side of the fix.
- `aj doctor` checks the claim the worker boundary rests on: as an owner
  (a member of a `w-*` group) it reads the mode of its own home and
  reports MISSING when the world bits are set (a worker is in no group of
  the owner's, so 0750 passes). The host's side, nixos-wsl: `homeMode =
  "700"` written out (the default; activation chmods the home to it
  every time) and `verify.sh` no longer accepts 755.
- `aj upgrade --workers` ran plain `bootstrap` as each worker, which
  never moves profile packages: after the first upgrade on this host
  both workers' `aj` was still the snapshot of their first bootstrap
  while the owner's was current. The worker now runs the same command
  as the owner. Seen because the upgrade printed the new skip lines for
  the workers (from `nix run <new snapshot>#aj`) while
  `~/.nix-profile/bin/aj` in each worker's home still pointed at the
  old build.
- The first live `aj init acme/infra` as a worker failed its last step,
  hook-test, with 106 "want 0, got 2": every allow refused. The hook was
  fine (run by hand in the jail it allowed `ls`); the harness's default
  cwd was `$HOME/code/git/acme/infra`, the runbook's example, which for
  the worker was the jail just created, and with HOME swapped for the
  scratch home direnv found no allow record for its `.envrc`. As the
  jailer the path never existed and the direnv check was skipped, which
  is why every earlier run passed. The default is now a path under the
  scratch directory that is never created; 443 pass as the worker.
- Checked after the rename, from a session in this checkout: every
  suite that runs without a Nix build passes, run by hand against
  stand-ins for the store paths (hook-test 373, install 81, host-config
  7, check-parser 93, project-settings 17/18/17, managed-tree 25 for
  linux and wsl, aj-bootstrap 271, aj-doctor 71, aj-init 82; ajmux 49 of
  54, the five being tmux refused its socket by the session's sandbox).
  Not run: `managed-host-eval`, `devenv-module-eval`,
  `claude-code-test`, statix and deadnix. Learned: the session's sandbox
  came from this checkout's own repo layer, which has no
  `allowAllUnixSockets`, so no `nix` command reached the daemon
  (`cannot create Unix domain socket: Operation not permitted`) and the
  CLAUDE.md "Checks" recipe could not run; `/proc/sys/user/max_user_namespaces`
  reads 0 inside the sandbox, so `aj doctor` run from a sandboxed session
  reports user namespaces MISSING on a healthy host. Fixed:
  `aj-bootstrap-test` read the host's `/etc/bashrc` (no
  `AI_JAILER_SYSTEM_BASHRC` pin, which `aj-doctor-test` has), so a run
  by hand on a NixOS host with `programs.direnv` failed where the Nix
  build sandbox, which has no `/etc/bashrc`, passed.
- Decision (the owner's), roadmap item 14: `git commit` joins the law,
  so the jailer's sessions are refused it too; the host's
  `allowLocalCommits` lifts it from law and jail together. hook-test
  gains the jailer's commit cases, managed-tree-test and
  `managed-host-eval` the law's `Bash(git commit)`. With the session's
  sandbox off the full `nix flake check` ran and passes; it caught two
  tests still asserting the old wording (check-parser's sandbox-off
  warning, aj-init's CLAUDE.md contract), fixed.
- Decision (the owner's), roadmap item 14, which reopens item 11 for the
  owner and supersedes item 13: the jailer is bound by the law only
  (credential reads, `git push`, and the managed-only keys until each
  is decided), the jail is the prisoner's and lives on the worker user,
  written by `aj bootstrap` and checked by the managed hook against a
  reference copy; `aj init` builds a cell. Item 13's option and its
  proposal patch are cut. Built the same day (the item has the list and
  the decisions made while building): the library's three bodies, the
  managed tree's `jail-settings.json`, the hook's law and jail rule sets
  and `jail_check`, bootstrap, doctor and reset for the jail, the docs.
  By hand: hook-test 439, managed-tree 36, project-settings 17,
  aj-bootstrap 257 of 280 with the same 23 failing on the committed tree
  under the session's sandbox; the flake checks not run (no daemon from a
  session). Learned: the sync keys honour user scope, so they belong in
  the jail, not the law; the law's credential rule must name `~/.ssh`,
  the GitHub token files and `~/.azure` by text, since the jailer has no
  sandbox `denyRead`; a stand-in `aj` for the bootstrap suite needs the
  store's bash and a tool directory built from `/run/current-system`, not
  `command -v`, which in this session resolved `grep` to the checkout.
- Decision (the owner's), roadmap item 13, which reopens item 11 for the
  owner: the ai-jailer checkout runs unsandboxed, and the sandbox moves
  from the managed body to each worker's user settings, with a hook rule
  that refuses a worker's tools unless `sandbox.enabled` resolves to
  true. Handoffs go to `proposals/` in the checkout, gitignored; the
  session scratchpad is private to the session. Built and staged:
  `lib/settings.nix`, `hooks/env-guard.sh`, `pkgs/aj/bootstrap.sh`,
  the tests, `flake.nix` (`project-settings-unsandboxed-test`); hook-test
  386, aj-bootstrap 280, project-settings unsandboxed 17, the others as
  above. The devenv module and this checkout's devenv.nix are
  `proposals/2026-10-28-unsandboxed-checkout.patch`. Until it is applied
  and the shell re-entered, a session here is still sandboxed.
- Decision (the owner's): the project is renamed. The repo and flake are
  `ai-jailer` (`bilibo/ai-jailer`; GitHub redirects the old URL, so
  existing `flake.lock` and `devenv.lock` files keep resolving), the CLI
  is `aj` ("ai-jailer, or `aj` among friends"), the tmux launcher is
  `ajmux`, and a governed repo is a jail: the devenv module's options are
  `ai-jail.*` (`ai-jail.enable`, `ai-jail.settings`, ...), a repo's
  `devenv.yaml` names the input `ai-jailer` and imports
  `ai-jailer/devenv`. Flake outputs: `packages.aj`, `packages.ajmux`,
  `apps.aj` and `apps.default`, so `nix run github:bilibo/ai-jailer --
  init` works. The `--harness <ref>` flag is `--jailer <ref>`. The two
  variables a jail's shell exports about itself are `AI_JAIL_PROJECT`
  and `AI_JAIL_PROJECT_DIR`; every other `HARNESS_*` variable is
  `AI_JAILER_*`. The host state bootstrap writes follows the name:
  `/etc/sudoers.d/ai-jailer`, `/etc/sysctl.d/99-ai-jailer.conf`,
  `~/.local/state/ai-jailer/receipt.json` (its ref and revision under
  the key `jailer`), `~/.cache/ai-jailer/direnv-ok`,
  `~/.config/environment.d/50-ai-jailer.conf`, and the
  `# --- ai-jailer ---` block markers in nix.conf, the bashrc snippet and
  tmux.conf. Unchanged: `/etc/claude-code`, the `w-` prefix, the `agents`
  group, the `devenv/` directory, the `claude-nix-harness-container`
  repo. Entries below keep the names of their day. A host bootstrapped
  under the old names (the 2026-10-22 laptops) holds state `aj reset`
  does not know: reset from the last old revision, a311cf4, first
  (runbook section 7). `bilibo/nixos-wsl` follows (input `ai-jailer`,
  package `ajmux`); its lock moves once the GitHub repo is renamed.

## 2026-10-27

- Finding: the owner verified that `harness bootstrap` then `harness
  init` on a fresh host ends with a repo that enforces nothing. A review
  of the tree at `ce6bd9f` found the cause: every hard rule of a work
  repo came from its own `.claude/settings.json`, which holds only when
  a chain of user-owned links holds (devenv evaluates, `direnv allow`, a
  store symlink that does not dangle, a session at the repo root, the
  trust dialog accepted, no `settings.local.json`, Claude Code >=
  2.1.295), and `harness init` checked one link. The documented command
  center never existed in a commit: this checkout ran `HARNESS_ROLE=work`
  with the sandbox on, and `devenv.yaml` imports `./devenv`.
- Facts checked against the Claude Code docs that day: managed settings
  are host-wide, with no per-user or per-group file. `strictAllowlist` is
  user-or-managed scope; `sandbox.enabled`, `allowUnsandboxedCommands`,
  `permissions.deny`, `denyRead`/`denyWrite`, `sandbox.credentials` and
  `allowedDomains` are any-scope; `allowManagedHooksOnly` is
  managed-only; `syncClaudeAiSkills` and `syncClaudeAiPlugins` honour a
  `false` from user, local or managed scope but not project scope. Deny
  lists merge across scopes. On Linux only a trailing `/**` works in
  `denyWrite` (a leading `**/` covers nothing). No documented switch
  leaves the sandbox network open; an empty allowlist prompts per host;
  a bare `*` in `allowedDomains` is undocumented for the sandbox list.
- Decision (the owner's), roadmap item 11, which reopens item 10: rules
  move to the host-wide managed tree and bind the owner's sessions too;
  one Linux user per org from `harness.workers` (`w-<org>`,
  0750 home, group `w-<org>` with the owner, marker group `agents`,
  linger, never in `trusted-users`, Home Manager per worker, user
  settings seeded once, never a store symlink); the host matrix stays
  and bootstrap mirrors the module on Fedora and Ubuntu; Claude Code's
  own sandbox stays, every `strictAllowlist` piece and the egress-filter
  idea go, `allowedDomains` stays as a prompt-avoiding list. Dropped:
  `harness.role`, `center-guard.sh`, `enforcementRoots`, the
  universal/project deny split, `HARNESS_ROLE`, `packages.managed-scoped`,
  `packages.project-settings-center`, the center and scoped checks,
  `docs/command-center.md`, bootstrap's user-scope settings block and
  `--account-sync`. The sudo rule is owner to workers only (`<owner>
  ALL=(%agents) NOPASSWD: ALL`), never a rule with `%agents` as the user
  list.
- Built and staged, not committed. `lib/settings.nix`: the managed body is
  everything plus `syncClaudeAiSkills`/`syncClaudeAiPlugins` = false; the
  repo body is the project layer (`extraDeny`, belt scalars, literal
  `denyWrite`, project domains, read fence) with no hooks.
  `lib/deny-rules.nix`: one list; the credential Read rules shrink to
  in-repo secrets plus `~/.ssh`, `~/.azure`, `~/.config/gh`,
  `~/.git-credentials`, `~/.claude/.credentials.json` and
  `~/.claude.json`. `lib/managed-tree.nix` and `lib/hooks.nix` lose
  roots, center and strict. `pkgs/devenv-cache.nix` is new: the shared
  cache URL and key.
- `hooks/env-guard.sh`: scoping removed, rule 3 shrunk, and a new
  universal rule refuses `direnv allow|permit|grant|edit` ("the human
  approves .envrc changes"). Learned (direnv 2.38.2 help): `grant` is
  another name for allow, and `edit` allows on editor exit. Side
  effects: a quoted mention such as `grep 'direnv allow' docs/` is
  refused, and `check_env`'s `fix: direnv allow <dir>` advice now names a
  command the hook refuses. `hooks/center-guard.sh` deleted.
- `nixos/default.nix`: options `owner`, `workers`, `ownerSudo`,
  `devenvCache`; users, groups, linger, sudo, `nix.settings` and the Home
  Manager branch; six assertions (user namespaces, owner required, owner
  not a worker, no worker or its groups, including `@agents` and
  `@wheel`, in `trusted-users`, names valid, names distinct). Learned:
  NixOS rejects a colon in the GECOS field, so the description reads
  `claude-nix-harness worker for <c>`; `users.users.<n>.linger` exists in
  the locked nixpkgs; `security.sudo.extraRules` accepts `runAs =
  "%agents"` and renders `raul ALL=(%agents) NOPASSWD: ALL`.
- `home/default.nix`: `userSettingsSeed` and the activation step
  `harnessSeedClaudeSettings`, which skips an existing file or symlink and
  runs after `linkGeneration`, not `writeBoundary`, so that an older
  generation's store symlink is gone first (suspected, from Home Manager
  knowledge; to verify in V6). `HARNESS_EXPECT_MANAGED` is gone.
- `devenv/devenv.nix` and `devenv.nix`, left as a patch for the human
  (`c1-devenv-module.patch` in the session scratchpad), because the hook
  refuses those files: role, memory and commit options gone, no hooks
  import, an unconditional warning when the managed file is unreadable.
  Until it is applied this checkout's shell fails to evaluate:
  `projectSettings` no longer accepts `centerRoot` or `sandbox`. The
  CLAUDE.md correction is the second patch (`f1-claude-md.patch`).
- `pkgs/ccmux.nix`: hands over with `exec sudo -u w-<c> -i ccmux
  <c>/<r>` when the caller is not that worker and the user exists; a
  worker naming another org is refused; a name with no clone under
  the caller's root still hands over; the window is `claude`;
  `XDG_RUNTIME_DIR` is exported (V5 pending). `pkgs/tmux.conf` loses the
  role line.
- `pkgs/harness/init.sh`: the hook test runs on the managed hook; no
  managed file is MISSING and exit 1; the template and the CLAUDE.md
  block are updated. `pkgs/harness/check.sh`: 18 cases, none skipped;
  case 4 is `cat .env`; case 10 expects
  `/etc/claude-code/hooks/env-guard.sh`; case 17 `sudo-text`; case 18
  `home-fence` (worker only).
- `pkgs/harness/bootstrap.sh` and `scripts/install.sh`: `--workers`,
  `--worker`, `--owner`, `--owner-sudo`. Root steps: the managed link
  (`nix build <ref>#managed --out-link /etc/claude-code`), then per worker
  groupadd, useradd, chmod, usermod and linger, and the sudoers file
  checked with `visudo -cf`. Then per worker `sudo -u w-<c> -i nix run
  <ref>#harness -- bootstrap --no-root --yes --harness <ref>`, and a git
  identity default. `reset` prints `userdel -r` rather than running it.
  `doctor` reports the managed file, runnable hooks, the `agents` group,
  linger, sudoers and the caller's standing. `--account-sync` is
  rejected. Learned: the harness wrapper puts real coreutils ahead of the
  test stubs, so `id`, `chmod` and `hostname` cannot be stubbed (the tests
  use `getent` and `uname -n`); `sudo -i` drops `HARNESS_REF`, hence
  `--harness` is passed.
- `flake.nix` and tests: the checks are now `ccmux-test`,
  `check-parser-test`, `devenv-module-eval`, `harness-bootstrap-test`,
  `harness-doctor-test`, `harness-init-dry-run-test`, `hook-test`,
  `hook-test-worktree`, `host-config-test`, `install-test`,
  `managed-tree-test`, `nixos-module-assertion`, `nixos-module-eval`,
  `project-settings-fenced-test`, `project-settings-root-test` and
  `project-settings-test`, plus `claude-code-test` (unfree).
- Results, each check run one at a time on a copy: hook-test 373 passed,
  hook-test-worktree 392; project-settings 17, fenced 18, root 17;
  managed-tree 22; ccmux 54; host-config 7; check-parser 93;
  harness-init 82; harness-bootstrap 243; harness-doctor 72; install
  77; nixos-module-eval and nixos-module-assertion pass with a
  two-worker fixture; devenv-module-eval passes against the patched
  module, tested from a copy with the module under another file name
  because the live hook refuses any file named `devenv.nix`, even under
  `$TMPDIR`. A full `nix flake check` on a copy of the staged tree with
  `c1-devenv-module.patch` applied exits 0 (2026-10-27); on the
  unpatched tree it stops at evaluation, because `devenv-module-eval`
  imports `devenv/devenv.nix`, which still passes `centerRoot` and
  `sandbox` to `projectSettings`.
- Not run: V1 the managed sandbox in a worker session with no repo file;
  V2 project-scope `allowedDomains` under a managed sandbox (decides
  whether `harness.extraAllowedDomains` stays in the devenv module); V3
  `allowedDomains = ["*"]`; V4 the owner attaching to a worker's tmux
  (`sudo -u w-x -i tmux attach` against `server-access`); V5
  `XDG_RUNTIME_DIR` under `sudo -i` with linger; V6 Home Manager seeding
  and `home.stateVersion` accepting "26.05" (the identity question is
  settled: the host's home-manager, nix-community at 6d9655f, takes it
  under `programs.git.settings.user`, which the host's own user block
  already uses, so the module's worker branch was changed to that form
  the same day); V7 group reads; V8 a `harness
  check` baseline; V9 managed `syncClaudeAiSkills = false` honoured.
  Also untested: `nix build --out-link` under sudo on a daemon host, and
  the whole `home-manager.users.<w>` branch (Home Manager is not an
  input of this flake).
- Accepted costs: the owner's sessions lose the unsandboxed center (`gh`,
  `~/.ssh` and pushes from a session stop working);
  `syncClaudeAiSkills = false` in managed settings binds the owner's
  account too.
- The first host build with a worker failed: `pkgs/claude-code.nix`
  (2026-10-24) added alsa-lib to the binary's RUNPATH with `patchelf
  --add-rpath`, and nixpkgs' version check then found claude-code
  2.1.303 (the host's nixpkgs, 02c087f) segfaulting on `--version`.
  Reproduced on the plain package: unpatched it runs; with the RUNPATH
  added after, before or in the same patchelf call as the interpreter
  change, and through autoPatchelfHook's `runtimeDependencies`, it
  segfaults. 2.1.308 (this checkout's nixpkgs) takes the same patch
  without harm; the cause is not known. The binary shows what the
  library was for: an embedded `bun-ant-audio-out` addon linked against
  `libasound.so.2`, extracted and dlopened for audio output. A RUNPATH
  on the executable is not searched for a dlopened object's own NEEDED
  entries (ld.so's rule, not tested live), so the 2026-10-24 form most
  likely never made audio work either. The override now removes the
  wrapper line and leaves the binary alone: audio output needs
  `LD_LIBRARY_PATH` and is not available from this package;
  `claude-code-test` now fails if the RUNPATH comes back. Verified:
  the override builds on both nixpkgs revisions with the version check
  on, and the test script passes 7 of 7 on each.
- Found evaluating `bilibo/nixos-wsl` with the module (a host with the
  Home Manager NixOS module): the README's `workers.acme = { };` failed
  with `harness.workers.test.gitEmail was accessed but has no value
  defined`, because the worker branch reads `gitName` and `gitEmail` and
  neither had a default. `nix flake check` missed it: Home Manager is not
  an input here, so the fixture never reaches that branch, and it set
  both anyway. Both now default to bootstrap's identity (`Claude (<c>)`,
  `claude-<c>@<hostName>.invalid`); the fixture's `acme` declares none
  and `nixos-module-eval` checks the defaults. Also learned there: the
  Home Manager NixOS module does not source `hm-session-vars.sh`, and
  the worker branch does not enable `programs.bash`, so a worker's
  `home.sessionVariables.HARNESS_CODE_ROOT` never reaches its shell.
  With the default `codeRoot` it does not matter (ccmux bakes the root
  in, and init and the devenv module fall back to `~/code/git`); a
  non-default `codeRoot` reaches ccmux only. Not fixed.
- Decision (the owner's), roadmap item 12, reopening item 11's NixOS
  module and Home Manager decisions: one route on every Linux, `harness
  bootstrap` from the harness checkout's devenv shell, which carries the
  CLI built from the checkout and sets `HARNESS_REF=path:<checkout>`;
  the host repo (`bilibo/nixos-wsl`) carries nothing of the harness but
  `ccmux` and the tmux rules, so it stays usable on non-WSL NixOS. Why:
  the NixOS module put the users, rules and options into the host
  configuration, and a second route meant two things to keep in sync.
- Done: `nixos/` and `home/` deleted with `nixosModules`, `homeModules`,
  `nixos-module-eval` and `nixos-module-assertion`; three assertions
  that lived only there (`failIfUnavailable`,
  `allowUnsandboxedCommands = false`, `Bash(nh os switch)` denied) moved
  to `managed-tree-test`. The host-wide options live in a gitignored
  `host.nix` at the checkout root (an attrset, or a function of `pkgs`),
  merged by `flake.nix` into `packages.managed`; `packages.managed-wsl`
  is the `platform = "wsl"` variant; `managed-host-eval` checks both.
  `pkgs/devenv-cache.nix` is the single source of the cache url and key:
  `pkgs/harness.nix` exports them to bootstrap. The root `devenv.nix`
  adds the `harness` package and `env.HARNESS_REF`.
- `bootstrap.sh`: the NixOS `NO_ROOT` exception is gone; NixOS runs
  the root steps with `nixos_nix_conf` (prints the `nix.settings` block,
  never writes or records `nix.conf`), the sysctl printed as
  `boot.kernel.sysctl` in `userns_steps`, no sudoers rule (an `info`
  line, `--owner-sudo` ignored), `managed_step` linking `#managed-wsl`
  under WSL, and `nixos_steps` with its `harness.*` lines deleted.
  Doctor's NixOS-only "no receipt" info line is gone, and
  `accounts_report` names a worker the receipt lists but `getent` lacks
  (`users.mutableUsers = false` at a rebuild). `root_write` also refuses
  `$STORE_DIR`; `root_link`'s refusal names the old module's
  `/etc/static` link. `scripts/install.sh` no longer prints its own
  `nix.settings` copy on NixOS and runs `worker_plan` there too, minus
  the sudoers lines.
- Learned: a `path:` ref under the owner's home is unreadable to a
  worker (0700 homes, NixOS and Fedora alike), so every per-worker
  bootstrap would have failed. `worker_user_steps` now prefetches the
  checkout into the store once (`nix flake prefetch --json`) and hands
  the workers that store path; open: the worker's `harness init` then
  pins that store path in `devenv.yaml` (roadmap item 12). Also learned:
  `writeShellApplication`'s `runtimeEnv` puts the cache url into the
  wrapper text, so a test that symlinked `nix.conf` to the wrapper
  stopped seeing the cache as missing; the test links a store directory
  now. Checked on the NixOS-WSL host: `setup-etc.pl` removes only `/etc`
  links into `/etc/static`; `/etc/sudoers` has no `@includedir`;
  `users.mutableUsers` is true.
- Tests: bootstrap 17 is the NixOS root-steps case, 24 the NixOS workers
  case (argv order as test 20 minus the sudo rule), 27 WSL linking
  `managed-wsl`, 28 a missing receipt worker, 29 the prefetched `path:`
  ref; doctor and install tests follow. 271, 71 and 81 pass. Untested
  live: everything of item 12's open list.

## 2026-10-26

- Hook rule 7, the tmux server (roadmap 2.8a), staged: inside the roots
  `tmux` passes only for read-only commands, by full name or alias (`ls`,
  `list-*`, `has-session`, `show-*`, `display-message -p` without `-I`).
  Prefixes are refused, and so are `-C`, a quoted or escaped `;`, `#(`,
  and `$`, backticks and globs in the arguments. A word after `tmux` that
  cannot be a command name (`grep tmux docs/`) is not counted as a call.
  The old env check is now rule 8. hook-test gains 72 cases, among them
  one known false positive, a quoted mention (`grep "tmux send-keys"`),
  refused for the same reason rule 6 refuses `bash -c "..."` text.
  `nix flake check` on a copy: every check passes. Learned on tmux 3.8,
  with a private server: an argument ending in `;` chains the next command
  (`tmux has -t s ';' display -p hi` ran both). Bare `tmux` without a
  terminal exits with `open terminal failed` before it creates a session.
  `#()` in `display-message -p` and `ls -F` did not run its job from a
  detached client; the rule refuses it anyway. Not yet live in this
  checkout: its hook is built from the working tree (`devenv.yaml` imports
  `./devenv`; CLAUDE.md's "pinned from GitHub" and `harness.role =
  "center"` describe a shape no commit carries, found 2026-10-26: the
  committed `devenv.nix` sets no role, and the shell exports
  `HARNESS_ROLE=work`), so the rule applies after the next devenv
  evaluation. The rule also applies in a center (it is a work repo's rule
  there).
- `harness check` case 16, `tmux-socket`, for rule 7 (roadmap 2.8),
  staged: `tmux new-window -d -n live-check 'true'` must be refused with
  `env-guard: tmux new-window blocked` (always run, the center too, since
  the hook refuses before tmux starts); `tmux display-message -p '#S'`
  must still pass and print the session name the script's own call in
  the same pane returns, run only inside tmux and skipped with a reason
  otherwise. Had the refused command run, the script (outside the
  sandbox) finds the new `live-check` window by id, kills it and fails
  `tmux-socket-state`, as case 15 restores `core.hooksPath`. Sessions:
  sixteen, eighteen fenced, eight in the center, one fewer each outside
  tmux (README, runbook). `check-parser-test` lists both halves. Not run
  live (rule 7 is not active here yet, and `harness check` starts real
  sessions); the first run should watch `tmux-display`, in case the
  session's environment scrub drops `$TMUX`.
- Roadmap 2.9, staged: with `allowMemoryEdits` the hook let the Edit and
  Write tools write any `~/.claude/projects/*/memory/*`, so a center
  session could seed a work repo's memory, which that repo's next session
  loads unreviewed with its own flag off. `check_edit` now allows only
  `~/.claude/projects/<slug>/memory/*`, `<slug>` being `CLAUDE_PROJECT_DIR`
  with every character outside `[a-zA-Z0-9]` made `-`; unset or empty, or
  a slug over 200 characters, means no carve-out. hook-test adds the own
  slug (one with `_`, `.` and capitals), another project's, a look-alike
  `-evil` suffix, a lowercased slug, a worktree project dir, and unset and
  empty; a mutation run against the old pattern fails exactly the six new
  refusals. All four hook-test checks pass (353, 384, 439, 372). The
  static deny rules (`lib/deny-rules.nix`, `claudeHome`) still leave
  every project's memory open: they cannot know the slug.
  `docs/command-center.md` section 7 describes the new shape. Learned: the
  slug is `path.replace(/[^a-zA-Z0-9]/g, "-")`, case kept, truncated to
  200 with a base36 hash suffix (sessions docs, "Where transcripts are
  stored"; read in the 2.1.308 binary), and auto memory is keyed on the
  canonical git root, so worktrees and subdirectories share the main
  root's directory (memory docs). Not verified: what `CLAUDE_PROJECT_DIR`
  is for a session started in a worktree or subdirectory (if that path,
  its own memory writes are now refused, fail closed; a test pins it);
  non-ASCII paths; a live memory save through the rule.
- Roadmap 2.7, staged: the `.envrc` that `harness init` writes fails the
  load while `devenv.local.nix` or `devenv.local.yaml` exists, with one
  line before `use devenv` (`error: <file> is refused in a harness repo
  (devenv loads it without a direnv allow): remove it and direnv reload,
  or move its content into devenv.nix as a proposed diff`), the line the
  hook's preamble shows; `check_env` names the fix for it instead of
  `devenv shell`, which skips the `.envrc`. devenv imports both files
  without a `direnv allow`, and the literal `denyWrite` that closed the
  interpreter write broke the shell (2026-10-22). With the template
  `.envrc` a `devenv.local.*` stops `harness init`'s shell step before any
  `direnv allow`; a repo that keeps its own `.envrc` still gets it shown
  and approved. A per-developer `devenv.local.nix`, including the
  per-developer `harness.enable = false`, is gone with it (README,
  project-devenv, runbook, command-center). harness-init-test 68 to 80.
  Learned on direnv 2.38.2: a failed load records no `watch_file` paths,
  only the `.envrc` and its allow/deny files, so removing the file needs
  a `direnv reload`; devenv's `use_devenv` keeps its watches by logging
  the error and exiting 0, which also means `check_env`'s exit test does
  not catch a devenv build failure (seen, not investigated). The live
  direnv runs were done in a nix build, because the hook refuses a shell
  write creating `devenv.local.*` even under `$TMPDIR`. Not live in this
  checkout until its `.envrc` gets the same lines by hand (the proposed
  diff is in the session report); existing repos get it with `harness
  init --force`. Its `harness check` case is not written.
- `harness doctor` prints `HARNESS_CODE_ROOT` (the default `~/code/git`
  marked when unset), `HARNESS_PROJECT` and `HARNESS_ROLE` as `info`
  lines after the harness ref line, so a verification starts by seeing
  which repo and role the shell is in; they are facts, counted nowhere,
  and a role without a project is a warning, since the repo shell's
  direnv exports both together (`pkgs/ccmux.nix`). The runbook's
  verification section starts there. harness-doctor-test covers unset,
  set and the pair (60 passed; harness-bootstrap-test 165). Learned: bash
  5 reads an apostrophe inside `${VAR:-...}` in double quotes as
  unbalanced, so the default text lives in a variable. Closes the first
  bullet of roadmap item 9. Run here, it printed `HARNESS_ROLE work` for
  this checkout, which is how the role finding above was made.
- Found, not fixed: the hook has no rule for `direnv allow` (or `permit`).
  In a work repo the gate holds because `~/.local/share/direnv/allow/` is
  not writable from the sandbox; in a center with the sandbox off a
  session can `direnv allow` another repo's `devenv.nix` after editing
  it, and its own after an interpreter write the hook does not see. A
  universal hook rule refusing `direnv allow|permit` with hook-test cases
  is the patch; a sandboxed checkout (`allowWrite` under the code root,
  roadmap item 10's set-aside proposal) would close it by construction.

- The NixOS-WSL host drops `harness bootstrap` (the user's decision): the
  host repo's configuration carries direnv (NixOS `programs.direnv`, with
  `pkgs/direnv.toml` as its settings), devenv, `harness` and `ccmux` from
  this flake as an input, the tmux rules through home-manager
  `programs.tmux`, and `HARNESS_CODE_ROOT`; `~/.claude/settings.json` is
  left to Claude Code and account sync. Found: the bootstrap had never run
  on that host, so `harness` was not on PATH at all, and the locked nixpkgs
  there (2026-10-20) ships direnv 2.38.2, so `pkgs/direnv.nix` is a no-op
  on it (this repo's own lock, 2026-10-14, still needs the override).
- `harness doctor` accepts that shape: `direnv.toml` is looked up under
  `DIRENV_CONFIG` (NixOS sets `/etc/direnv`); a store link there is taken
  as is, like home-manager's, and a plain file is judged by `strict_env`
  and `load_dotenv`; the bash hook may be in `/etc/bashrc`
  (`HARNESS_SYSTEM_BASHRC` in the tests); no receipt on NixOS is an info
  line; the `environment.d` PATH is not checked when direnv is a system
  package; and `sandbox.network.strictAllowlist` missing is MISSING only
  when a receipt exists (bootstrap wrote it), a warning otherwise.
  `harness-doctor-test` gains 8 cases. Tried on the NixOS-WSL host with
  `nh os test` and this checkout as the `harness` input: 1 missing
  (mkhl.direnv, below), 2 warnings (the allowlist, account sync).
- `mkhl.direnv` on WSL is an info line, not MISSING (the user's decision):
  installed on the Windows side it only raises errors, and in the WSL
  remote it is a manual "Install in WSL", since nothing provisions VS Code
  extensions there. Without it, VS Code's own processes (the Claude Code
  extension, language servers, tasks) run outside the repo's devenv
  shell; only terminals that `cd` into the repo get it. Other hosts keep
  MISSING: bootstrap installs it there. `harness-doctor-test` gains 3
  cases.
- nixpkgs bumped (2026-10-14 to 2026-10-23, the user's go-ahead), which
  ships direnv 2.38.2, and `pkgs/direnv.nix` deleted: `flake.nix`,
  `nixos/default.nix`, `home/default.nix`, `lib/managed-tree.nix` and
  `devenv/devenv.nix` (a guard-rail file, edited from an unsandboxed
  session with the user's go-ahead) use `pkgs.direnv`, and the home module
  asserts >= 2.38. `nix flake check` on a copy: every check passes.
- Found: with only `flake.lock` bumped, this checkout's sessions refused
  every Bash command with `direnv: error exit status 127`. The devenv
  module's hook puts its own direnv first on PATH, and that one comes from
  the dev shell's nixpkgs (`devenv.lock`, still 2026-10-14: direnv
  2.37.1), where the `.envrc`'s `require_allowed` is not a command.
  `nix flake check` did not catch it: the hook tests run a stub direnv.
  `devenv.lock` bumped to the same nixpkgs; Bash commands pass the hook
  again. The devenv module has no version assertion yet.

## 2026-10-24

- The Windows route moved to the host repo (the user's decision), staged
  in both repos. `scripts/install-wsl.ps1` and `scripts/wsl/bootstrap.sh`,
  `update.sh` and `verify.sh` left this repo for `bilibo/nixos-wsl`'s
  `scripts/` (`git rm` here, `git add` there, content kept as the starting
  point). Why: a host provisions itself from its own checkout on Windows
  and that checkout becomes `/etc/nixos`, while the harness is a user tool
  whose part starts at `harness bootstrap`, the same as on any NixOS; so it
  keeps no Windows installer. There, `-HostRepo` is optional and defaults
  to the checkout's `origin` URL (`git -C <checkout> remote get-url
  origin`), else the checkout folder; `-Output`, `-Tag`, `-NoSwitch` and
  `-SkipVerify` are unchanged, and Done lists bootstrap, a new terminal,
  `harness doctor`, the clone under `~/code/git/<org>/` and `harness
  init`. The in-distro update is `sudo sh
  /etc/nixos/scripts/wsl/update.sh <name>`. The README (host table, the
  Windows section, layout), runbook section 4, the roadmap's Done entry (a
  dated note) and the comments in both `examples/nixos-wsl-*.nix` point at
  the host repo's installer; nixfmt, statix and deadnix clean. No check
  used the moved files: on copies of the tree before and after, every
  `checks.x86_64-linux` drvPath (19) is the same, `nix flake check` on the
  copy is green (every output already in the store), and `install-test`,
  the one check that reads `scripts/`, passes forced with `--rebuild` (60
  of 60). `verify.sh` from its new place on the still-managed
  host: 18 ok, 1 failed (HTTPS to cache.nixos.org, which the session
  sandbox blocks). Learned: the 2026-10-23 install took the host repo as a
  Windows folder without `.git`, so `/etc/nixos` became one baseline commit
  with no remote and `update.sh` had nothing to pull; and since the script
  takes the update path whenever `/etc/nixos` is a checkout, a rerun
  rebuilds that baseline, not the pushed repo. Defaulting to the origin URL
  makes the first install a clone with a remote; the live host needs a
  fresh install (`wsl --unregister`) or its `/etc/nixos` pointed at origin
  once (nixos-wsl README). And a script kept in the repo it deploys
  updates itself: `update.sh` run from `/etc/nixos` pulls over its own
  file, which holds because git replaces a file (unlink, then create)
  rather than rewriting it, so the running shell keeps reading the old one.
- The command center is deliberately open (the user's decision): it is
  where new repos are set up, and locking it down is a choice
  (`harness.role = "work"` in its `devenv.nix`, or doing the work from a
  locked repo). A center session may write other repos' `devenv.nix`,
  `devenv.yaml`, `devenv.lock`, `.envrc` and `.claude/` skills, agents,
  commands and hooks, by the Edit tool or by one shell command naming the
  file's absolute path; such changes show in `git diff` and take effect
  only after `direnv allow` in that repo. Its own root and the module
  source stay closed, and so does every repo's `.claude/settings*.json`
  and `devenv.local.*`, which switch rules off without either. Git
  history, launch-flag, sudo, credential, cloud and memory rules are
  unchanged. `hooks/center-guard.sh` is spliced into the center's hook
  only (`lib/hooks.nix`, `substitute --replace-fail`, so a moved splice
  point fails the build), and the center's deny rules name its root as
  `//<root>/…`. Learned: a work hook that merely carried an empty
  `CENTER_ROOT` would have moved every work repo's hook and settings
  store path, so the center's code lives outside `env-guard.sh` and the
  work role is proven unchanged by store path. Where a shell command
  writes cannot be read from its text: `cd`, `-C`, a `$(…)` with a space
  in it, a glob or brace, `~+`, `/proc/self/cwd`, or a copy's destination
  directory all hide it. Checking only the config-file word would have let
  `cp <other>/devenv.nix .` and `echo x > $(echo <root>)/devenv.nix`
  through, so only one simple command with absolute paths is relaxed, and
  `cd` is not followed. hook-test-center: 362 cases, 19 of which today's
  hook refuses (exactly the newly allowed ones). Left, in both roles: the
  shell rule does not recognise `.claude` without a trailing slash (`rm
  -rf <repo>/.claude` passes), and hard links are not detected; in a work
  repo the sandbox holds, in the center the prompt does.
- The plain WSL host gets tmux and no `claude` (the user's decision),
  staged. Claude Code there is the VS Code extension on Windows, whose
  bundled binary runs inside WSL over Remote-WSL; work repos bring a CLI
  `claude` (and tmux) for tmux/`ccmux` sessions through
  `harness.claudeCode.enable`. `examples/nixos-wsl-plain.nix` and the
  nixos-wsl host add `tmux` to `environment.systemPackages`, with a comment
  saying why `claude` is absent; `scripts/wsl/verify.sh` judges `tmux on
  PATH` on a plain host and keeps `claude` as info, naming the extension
  and `harness.claudeCode.enable`; nixos-wsl's `check-access.sh` does the
  same (23 checks plain, 25 managed); `install-wsl.ps1`'s Done message
  says where Claude Code comes from. Both nixos-wsl outputs dry-run, with
  tmux-3.8 and no claude-code in systemPackages. `harness init` looks for
  `claude` on the host PATH, skipping Nix-store directories (a repo
  shell's) and `~/.vscode-server`; with none it writes `claudeCode.enable =
  true;` uncommented and `allow_unfree: true` in devenv.yaml, with one it
  leaves both commented out, and its report's `claude` line says which.
  `harness doctor` reports a missing host claude as an `info` line,
  counted nowhere, instead of MISSING, and a missing tmux as a warning,
  since ccmux carries its own tmux; an old host claude is still MISSING.
  `ccmux` takes claude from PATH by absolute path, else runs `direnv exec
  <repo> claude` in the window, and with neither exits 69 naming
  `harness.claudeCode.enable`; `-n` prints a third line, `claude=<path>
  (<source>)`. `harness check` runs its sessions with the `claude` a
  terminal in the repo gets, by absolute path: this shell's own when it is
  the repo's; else `direnv exec <repo>`'s, the repo shell's or the host's
  beneath it, never another shell's; else a host `claude` outside the Nix
  store. With none it exits 69 naming `harness.claudeCode.enable`, before
  any session; the header and `--dry-run` print a `claude:` line.
  harness-init-test 55 to 68, harness-doctor-test 29 to 38, ccmux-test 37
  to 45, check-parser-test 151 to 168. Learned: the extension's bundled `claude` is a
  dynamically linked glibc ELF, so on NixOS it runs only through
  `programs.nix-ld`, which both host files keep; a `claude` on PATH inside
  a repo shell is that shell's, not the host's, so init run from the
  center's shell would otherwise have left a work repo without its CLI;
  and tmux takes a new window's PATH from the client that runs
  `new-window` or `new-session`, even from inside tmux, and the rest of
  its environment from the server's global one (tmux 3.7c), so ccmux
  passes the absolute path and the window runs exactly what `-n` reports.
- `ccmux` carries the role, and hook rule 6 covers `ccmux`, staged. A
  window `ccmux` opens in the shell's own project (`HARNESS_PROJECT`) is
  named after `HARNESS_ROLE` and exports it. A window in any other
  project is named `claude` and runs `unset HARNESS_ROLE` first, so a
  work session launched from the center never reads `center` and its
  repo's shell sets `work`. ccmux also drops the variable from its tmux
  client, and `pkgs/tmux.conf` adds `set-environment -gu HARNESS_ROLE`
  next to the project variables (`host-config-test` checks it), so a
  server it starts has none globally and a window opened by hand from a
  center shell carries none either. `ccmux -n` prints a second line,
  `role=<role|unset> window=<name>`. Rule 6 now matches `ccmux` as well
  as `claude`, and for `ccmux` outside the enforcement roots too, since it
  only launches into the code root. Until today `ccmux <c>/<r>` with
  `--bare`, `--setting-sources user`, `--settings`, `--permission-mode`,
  `--dangerously-skip-permissions` or `--add-dir` passed (`--plugin-dir`
  was already refused by rule 5). hook-test 252 to 277, hook-test-scoped
  279 to 306, hook-test-worktree 271 to 296, ccmux-test 25 to 37 (five
  live, on a private tmux server); the new cases fail on the old hook and
  the old ccmux. Learned: tmux gives a new window the server's global
  environment, which belongs to whichever client started the server, not
  to the launching shell. With the old ccmux, on a server a center shell
  had started, even a work repo's own `ccmux` opened a window with
  `HARNESS_ROLE=center`, so the window now sets or clears the role
  itself. And rule 6 had a hole for `claude` too: the normaliser strips
  quotes before the rule stops arguments at `;`, `&` or `|`, so `claude
  -p "a; b" --bare`, `claude -p a\; b --settings x.json` and `claude -p
  hi 2>&1 --bare` passed. The rule now reads a copy of the command with
  separators inside quotes, after a backslash and in `2>&1`/`&>` turned
  into `_`, which can only add matches; one extra `jq` per Bash call, and
  a `jq` failure denies the command. Left: an unquoted `$(a; b)` between
  the launcher and the flag, and a renamed binary; the text rule is a
  tripwire, not a boundary.
- The command center gets its own shell (the user's decision, 2026-10-24
  afternoon; it replaces the morning's assumption that the center keeps
  the sandbox). New devenv option `harness.role`. `work` (the default) is
  today's file. `center`, set in this checkout's `devenv.nix`, writes the
  same deny rules and hook with `sandbox.enabled = false` and only the
  credential list under it: no network allowlist, no filesystem
  confinement, `/mnt/c` readable, and every Bash command goes through
  Claude Code's permission prompt. The owner's
  `harness.settings.permissions.allow = [ "Bash(*)" ]` quiets the prompts;
  deny rules and the hook still win. Memory and `claudeCode.enable`
  default on there, `readFence` is ignored, the shell adds nixfmt, statix,
  deadnix and shellcheck, and `HARNESS_ROLE` is exported. `ccmux` names
  the window after the role and starts a window into another project with
  `HARNESS_ROLE` unset, so a work session launched from the center never
  reads `center`. The checkout's `devenv.yaml` imports `harness/devenv`
  pinned from `github:bilibo/claude-nix-harness` instead of `./devenv`: an
  agent's working-tree edit to `hooks/` or `lib/` no longer becomes its
  live hook at the next shell entry, and the rules move when the human
  runs `devenv update harness`. Hook rule 6 now refuses `ccmux` with the
  nested-`claude` launch flags (`--bare`, `--setting-sources`,
  `--settings`, `--permission-mode`, `--add-dir`, ...) everywhere, and
  reads quoted separators as text. The module and root-file changes are
  patches for the human (`module.patch`, which contains the off switch,
  and `center.patch`, which replaces `cc.patch`; both next to the repos
  under `~/code/git/bilibo/`), because the hook refuses `devenv.nix`,
  `devenv.yaml` and `devenv/devenv.nix` to a session.
  `docs/command-center.md` is rewritten; `docs/sessions.md` section 3 and
  handoff phase 2 say the tier is realised as the role.
  `project-settings-center-test` (15 checks) and the center cases in
  `devenv-module-eval` are new; with `role = "work"` the generated file
  and both managed trees keep their store paths, so nothing changed for a
  work repo. Learned: turning the sandbox off removes everything it did
  against scripts, not only the credential reads. A script in the center reads
  `~/.ssh`, `~/.aws`, `~/.azure` and the gh and git tokens, reaches any
  host, and writes wherever the user can: `~/.bashrc`, `~/.config`, the
  user-scope `~/.claude/settings.json` that holds the work repos'
  strict-allowlist key, and any repo's git config via `git config
  core.hooksPath`. The hook only sees command text, and `gh pr merge` or
  `gh api` are not git commands. The Bash prompt is the one layer left,
  and `Bash(*)` removes it. Whether `sandbox.credentials` still strips the
  secret variables with the sandbox off is unverified. `devenv update`
  passes every rule, so a session can move a lock (only to what the input
  URL serves). On a managed host the managed `sandbox.enabled = true`
  wins, so `center` turns nothing off there. The tmux-socket hole (roadmap
  2.8) no longer concerns the center, but the center's pane is one a work
  session can type into.
- The `harness` CLI knows the role. `harness check` reads the repo's
  `.claude/settings.json`: with `.sandbox.enabled` not true and the repo's
  `HARNESS_ROLE` = `center` (this shell's when it is that repo's, else
  `direnv exec`), the cases only the sandbox holds (1 sandbox, 8
  ssh-agent, 9 home-write, 11 repo-write, 12 env-deny, 14 cred-sandbox, 15
  git-hookspath; 13 read-fence when fenced) print `skip  <case> sandbox
  off (role center): <why>` and start no session, and no fake
  `~/.git-credentials` is written; the hook and deny-rule cases run as in
  a work repo, seven sessions instead of fourteen. The summary reads `N
  passed, M failed, K skipped`. A repo whose file has the sandbox off but
  whose role is not center gets a warning and every case, so a work repo
  that lost its sandbox fails instead of skipping. `harness init` writes
  `# role = "center";` commented out under `# enable = false;`, marked as
  the harness checkout's only. It prints the role the shell exports. For
  `center` (the harness checkout, which `scripts/install.sh` initializes)
  it runs the settings test in its center mode, and warns without
  stopping when the repo has no `devenv/devenv.nix` and `lib/settings.nix`
  of its own. Its `ccmux -n` note joins ccmux's new role/window line with
  `; `. `harness doctor` is unchanged: its repo checks do not depend on
  the role. `check-parser-test` grows from 9 to 151 assertions (dry runs
  on fake repos per sandbox state and role), `harness-init-dry-run-test`
  from 42 to 55; `docs/project-devenv.md` has a `role` row. Learned: half the live
  cases are held by the sandbox alone. `touch ~/.claude/...`, `mkdir
  .claude-plugin` and `git config core.hooksPath` pass the hook (no word
  it treats as a write, no protected path in the command text), so in the
  center an ordinary permission prompt is the only layer there. The center
  keeps `sandbox.credentials`, but whether it applies without the sandbox
  is unverified, so its two cases skip rather than claim either way. The
  hook also refuses the Write tool on any `.claude/settings.json`, even
  under `$TMPDIR`, so `harness check` fixtures are built in the Nix build
  sandbox, as the tests do. Not yet run live.
- An off switch for a repo, staged: `harness.enable` in the devenv module,
  default `true`. `false` (one line in the repo's `devenv.nix`, then
  `direnv allow`) writes no `.claude/settings.json`, so the repo has none
  of its deny rules, hook or sandbox, exports no `HARNESS_*` variables, and
  prints `harness: guard rails off for this repo (harness.enable = false in
  devenv.nix)` at every shell entry. ccmux and the `claudeCode.enable`
  packages stay: tools, not rules. A managed host's root-owned settings
  apply regardless. The module change, merged with the staged
  `pkgs/claude-code.nix` swap, is one diff for the human, since the hook
  refuses `devenv/devenv.nix` from a session. `harness init` writes the
  line commented out, first in the `harness` block, and on a repo whose
  shell loads without the harness (`DEVENV_ROOT` set, no `HARNESS_PROJECT`)
  reports `off` and exits 0 instead of saying the shell did not load.
  `harness-init-dry-run-test` grows from 35 to 42 assertions; the new
  `devenv-module-eval` check evaluates the module under `lib.evalModules`
  with stand-ins for devenv's options: on, it writes exactly the
  `project-settings` fixture; off, nothing. `docs/project-devenv.md` has
  "Turning the guard rails off (and on)". Learned: devenv 2.4's files
  module records what it linked in `.devenv/state/files.json` and removes
  a store symlink that drops out of `files` at the next entry, so
  switching off needs no cleanup step (read from the source; not yet seen
  live). And the switch opens nothing new: whoever can write `devenv.nix`
  could already turn the sandbox and hooks off through `harness.settings`,
  which is merged over the generated file. What keeps an agent from it is
  the `Edit(**/devenv.nix)` deny rule and the hook's text match, not the
  sandbox: `devenv.nix` is not among the literal `denyWrite` paths.
- NixOS-WSL is a plain host by default (the user's decision, 2026-10-24).
  The Windows route no longer makes the distro a managed harness host: the
  host flake carries NixOS-WSL and the sandbox prerequisites only (user
  namespaces, bubblewrap and socat, flakes and the devenv cache,
  `allowUnfree`), and the harness comes afterwards as the user, `nix run
  github:bilibo/claude-nix-harness#harness -- bootstrap`, then `harness
  init` per work repo; guard rails hold inside those repos only. The
  managed modules stay as the stricter opt-in (`examples/nixos-wsl-host.nix`).
  New `examples/nixos-wsl-plain.nix`, evaluated as a NixOS-WSL system
  against the host repo's pinned inputs; nixfmt, statix and deadnix clean.
  `scripts/wsl/verify.sh` keys on `/etc/claude-code/managed-settings.json`:
  on a plain host it prints "unmanaged host: managed-layer checks skipped",
  reports direnv, devenv, ccmux and claude without judging them, and prints
  the bootstrap command while `harness` is absent; a managed host keeps all
  19 checks. `install-wsl.ps1` changed wording only, plus the next steps
  at Done and `-SkipVerify` in its help. The nixos-wsl host repo dropped
  its `harness` input (lock pruned offline), both module imports and
  home-manager's `programs.bash.enable`, and gained a basic toolset (dig,
  micro, vim, jq, ripgrep, ...); both outputs evaluate (`nix build
  --dry-run`), not yet switched in. Learned: home-manager owning
  `~/.bashrc` blocks the bootstrap on NixOS (it skips a store-symlinked rc
  file and only prints the option), so a host that wants the harness
  installed as the user leaves bash to the user; and the system's
  `nixpkgs.config.allowUnfree` is read neither by the bootstrap's `nix
  profile add` (pure flake evaluation) nor by a repo's shell (`allow_unfree`
  in devenv.yaml), so it only matters for unfree packages in the system
  configuration itself. Open: the bootstrap's profile is direnv, devenv,
  ccmux and `harness`; on the plain box `claude` and `tmux` come from
  nowhere until the native installer, `nix profile add
  github:bilibo/claude-nix-harness#claude-code`, or a repo's
  `harness.claudeCode.enable` provides them, and `harness doctor` says so.
- The command center (decided 2026-10-24): the host becomes a plain box
  with no host-wide rules, work repos keep the full set, and this
  checkout is where a human starts the session that launches and reviews
  the others. `docs/command-center.md`, new: starting it, what it can and
  cannot do (file:line), the memory decision, the known gaps.
  `allowMemoryEdits = true` was already set in the root `devenv.nix`; the
  decision makes it the command center's alone, and the comment change
  there is a patch for the human (the hook refuses the file from a
  session). Checked with 41 synthetic events against this checkout's own
  hook build (`ALLOW_MEMORY_EDITS="1"`, no roots): every `git -C <path>`,
  `cd <path> &&`, `bash -c`, `sh -c`, `--git-dir` and `GIT_DIR=` form of
  commit, push and reset refused; `diff --cached`, `log`, `status`
  through `git -C` pass. Learned: a session's rules come from where it
  starts, so the command center carries every universal, git and cloud
  rule itself; hook rule 6 matches `claude`, not `ccmux`, so `ccmux
  <c>/<r> --setting-sources user` or `--bare` passes; the memory
  carve-out admits any project's memory, a work repo's included; devenv
  tracks `hooks/` and `lib/` as inputs and `require_allowed` does not
  cover them, so a working-tree edit there becomes this checkout's live
  hook at the human's next shell entry, before any commit; devenv also
  imports `devenv.local.nix` from an imported directory. And the tmux
  socket: `allowAllUnixSockets` reaches the tmux server outside the
  sandbox and no rule covers it; no server ran during the check, so `tmux
  ls` from the sandbox answered `couldn't create directory
  /run/user/1000/tmux-1000 (Read-only file system)` (the directory
  absent): reachability inferred from the 2026-10-21 gcr measurement,
  not observed. Roadmap 2.8 and 2.9.
- Mods dropped, roadmap item 8 closed: the harness ships no mods. A mod is
  a hooks module the engine loads into every session on the machine,
  outside the Bash sandbox, and an enabled organisation mod is the one
  kind the built-in guard lets through; the broker would have made its
  code, build, marketplace and registration keys a surface the harness
  defends on every host, for coordination that never relaxes a rule.
  Removed: `mods/` (the broker's observe slice, its types and five `claude
  plugin test` cases), `lib/mods.nix` (`mkMod`, `mkMarketplace`), the
  `harness.mods` option, the managed tree's `plugins/` directory, the
  `extraKnownMarketplaces.harness` and `enabledPlugins` keys,
  `packages.managed-mods` and `packages.harness-broker`,
  `tests/mod-validate-test.sh` and its unfree-only check. Kept, and
  asserted on both managed trees by a rewritten `managed-tree-test` (20
  checks) and on the module's tree by `nixos-module-eval`: the guard's
  `allowManagedModsOnly`, `disableSideloadFlags`, `allowManagedHooksOnly`,
  and `strictKnownMarketplaces`, now `harness.extraKnownMarketplaces`
  alone, empty by default so no marketplace can be added.
  `docs/sessions.md` loses the broker (section 5 is a dated note;
  coordination stays the proposal flow and `ccmux`); the handoff's
  platform tier keeps the `claude plugin` rule whole. The bootstrap's
  `--no-account-sync` is now the default: `syncClaudeAiSkills` and
  `syncClaudeAiPlugins = false` go into the user-scope
  `~/.claude/settings.json` on every bootstrap and upgrade (recorded in
  the receipt, removed by `reset`); `--account-sync` opts back in and
  removes a `false` already there; `--no-account-sync` is still accepted;
  doctor's warning names `--account-sync`; `harness-bootstrap-test` 165
  checks. Learned: the repo file never carried any of the mod wiring (the
  `project-settings` derivations did not change with the removal), so the
  machinery was managed-host surface only; the managed directory in
  `strictKnownMarketplaces` existed only to admit the harness's own
  marketplace; with only `false` honoured for the sync keys, an opt-in
  flag has to delete the `false`s or it does nothing on a host
  bootstrapped since; and because `harness upgrade` hands the original
  flags to the upgraded bootstrap, a host bootstrapped with no flag gets
  sync off at its next upgrade. Not verified: an empty
  `strictKnownMarketplaces` meaning "no marketplace can be added" is the
  settings reference's reading (not re-read today: no network to the docs
  from the session), and no managed host has loaded either tree.
- The `LD_LIBRARY_PATH` fix, staged: `pkgs/claude-code.nix` overrides
  nixpkgs' claude-code to drop `--prefix LD_LIBRARY_PATH` from the
  wrapper and put alsa-lib on the binary's RUNPATH instead (`patchelf
  --add-rpath` in `postFixup`, after autoPatchelfHook), so a dlopen from
  the binary still finds libasound and no child process sees the
  variable. The override asserts the line is there to remove: when
  nixpkgs stops setting it, the build says to delete the file, the exit
  `pkgs/direnv.nix` has. The home module takes it through a new
  `harness.claudeCodePackage` option (default the override), the flake
  exports `packages.claude-code`, and `claude-code-test` (7 checks)
  asserts the wrapper no longer names the variable and keeps its PATH
  prefix, the binary carries the RUNPATH, and `claude --version` still
  answers; unfree, so the package and the check exist only when the
  evaluator allows it, as `mod-validate-test` already did. The devenv
  module's one-identifier change (`pkgs.claude-code` to the override
  under `claudeCode.enable`) is a diff for the human: the hook refuses
  `devenv/devenv.nix` from a session. Not the hook preamble: it would
  have covered the Bash tool only. Learned: `lib.hasInfix` is
  `builtins.match` underneath and refuses a string carrying a store-path
  context, so the assertion compares the `replaceStrings` result with
  the original.
- `docs/suggestion.md`, new: two ideas with a shape, neither a roadmap
  item. Agents built on the Claude Agent SDK, on what its documentation
  says (read the same day): a session loads project settings and hooks
  by default, so an SDK program in a harness repo is governed like a
  session; managed settings load whatever the program asks for; the
  program's own `settings` and `sandbox` rank above project scope, so
  on an unmanaged host an opt-out program escapes the repo file; and
  whether `disableBypassPermissionsMode` stops the SDK's own bypass mode
  is not documented, which is the test case (the SDK form of
  `docs/sessions.md` section 7's question). A first draft had the
  default backwards and called the broker an SDK candidate; it is a mod
  inside the engine. And the agent's cloud identity (Entra Agent ID) as
  a separate repository: the handoff's `azure-<actor>` split already
  gives the agent its own `AZURE_CONFIG_DIR`, but with `agentAuth =
  user` it holds the human's identity, so the tenant cannot tell the
  two apart; a third `agentAuth` value, a doctor line comparing the two
  principals, a detection pairing by app id and host, attestation
  through a future `harness doctor --json`. The roadmap's Ideas and
  `CLAUDE.md` point at it.
- Traced the `LD_LIBRARY_PATH` open question (roadmap, 2026-10-21): it
  comes from Claude Code's own nixpkgs package. `bin/claude` in
  `claude-code-2.1.300` is a `makeBinaryWrapper` binary whose embedded
  invocation has `--prefix 'LD_LIBRARY_PATH' ':'
  '/nix/store/xlqm12gx...-alsa-lib-1.2.16.1/lib'`, next to `--set
  USE_BUILTIN_RIPGREP 0` and a PATH prefix (procps, ripgrep, bubblewrap).
  That path is the whole of `LD_LIBRARY_PATH` in this session. The
  sandbox's own process (PID 2 in its namespace) already has it, and
  neither the shell snapshot nor the devenv export sets it, so every
  hook and Bash command inherits it from the `claude` process. It hits
  every host where Claude Code comes from nixpkgs: the managed host (the
  home module's package) and any repo with `harness.claudeCode.enable`,
  this checkout included. A host binary linked against the distro's
  glibc (VS Code's `code`) then loads Nix libraries and dies. Not
  changed: whether the hook preamble should strip that one entry is
  left open in the roadmap.
- Roadmap 0.8, staged, not yet run live: `harness check` case 14
  (`cred-sandbox`), the sandbox's own `denyRead` on `~/.git-credentials`
  with the hook out of the way. Two departures from the roadmap's
  sketch. First, the command is `wc -c ~/.git-cred*`, a glob, not
  `${f}credentials`: case 2 records that `-p` refuses `${...}` before
  it runs, which would leave the case inconclusive every time. Second,
  the forbid is a non-zero size, not `live-check`: `wc -c` never prints
  content, so a real file stays unread even if the sandbox fails. Seen
  in this session, under the same sandbox: the glob matched nothing. A
  masked file would still be listed, so the host evidently has none and
  a `denyRead` path is not masked into existence (a `denyWrite` path is,
  case 11). So the case creates
  the fake file (mode 600) when there is none, removes it after, and
  leaves an existing one alone. It passes on `0 <path>` (masked as
  `/dev/null`, as the README says of `.env`), on no such file, or on a
  permission error; the first live run says which. The header's session
  counts were off before this: cases 1 to 12 are twelve sessions, a
  fenced repo adds two (case 13 runs two), a failed case 2 adds two
  diagnose sessions. With case 15 (next entry): fourteen, sixteen and
  two, and the README and runbook say fourteen.
- Roadmap 2.6 answered, staged as `harness check` case 15
  (`git-hookspath`): the main checkout's `.git/config` holds against a
  shell write. Run in this session, under the same sandbox,
  `git config core.hooksPath /tmp/live-check-hooks` (and before it a
  harmless `harness.livecheck` key) exits 255 with `could not lock
  config file .git/config: File exists`, and the value stays unset. git
  writes through `.git/config.lock` and a rename. `.git/config` itself
  is a read-only bind of the real file, and the sandbox mounts
  `/dev/null` at `.git/config.lock`: a character device, `nobody`, seen
  only inside the sandbox. So the lock cannot be taken. The roadmap
  expected a permission error; the case accepts either. The hook has no
  rule for the command, so the sandbox is the only layer. Not covered:
  `-c core.hooksPath=`, `--global` and a worktree's own config (runbook
  section 8 now says so). The case saves and restores the key if the
  write ever lands, and it fails when `.git` is not a directory.
- Roadmap gap C, staged: `docs/project-devenv.md`, the project devenv for
  a human who does not know Nix. The files and who edits them, the
  four-step loop every change goes through, then tools, unfree packages,
  toolchains, `env.` lines, allow rules, network hosts and the other
  options, each with the lines to paste. Two things learned writing it.
  First, a toolchain's package manager needs the network: cargo, pip and
  npm reach hosts the default allowlist leaves out, while Nix fetches
  `packages` outside the sandbox, so the guide names the hosts for
  `extraAllowedDomains`. Second, `harness.settings` is merged with
  `recursiveUpdate`, so a list there replaces the harness's own:
  `settings.permissions.deny` or `settings.sandbox.network.allowedDomains`
  would drop the full deny set or the allowlist. The guide says to use
  `extraDeny` and `extraAllowedDomains`; nothing in the module stops it
  yet. The guide repeats the 2026-10-23 finding that `require_allowed`
  flags an edited `devenv.nix` without blocking it. The template
  `harness init` writes links the guide in its header and gains
  commented `packages`, `languages` and `env` lines (the rendered file
  parses; harness-init-test 35). Linked from the README, runbook section
  3 and `CLAUDE.md`.
- Roadmap 0.3 and 0.6, staged. `harness bootstrap` no longer runs dnf,
  labels the daemon socket for SELinux or enables the socket:
  `scripts/install.sh` does all three before `nix run` exists, and the
  bootstrap copies had been dead weight since the one-route decision
  (2026-10-21). The SELinux explanation moved into `install.sh`, which
  pointed at bootstrap for it. `reset` still undoes those steps from the
  receipt and `doctor` still reports them. bootstrap-test case 11 is now
  `doctor` on a Fedora 44 os-release: the host line, and no dnf call
  (150 checks). `harness init` treats a `devenv.lock` that is there
  before the first load as foreign and prints its pinned inputs (`name:
  type:owner/repo @ rev`) instead of the raw file; harness-init-test has
  a repo with only a lock (35 checks; 3 of them fail against the old
  `init.sh`). Side effect: a re-run of `harness init` on a repo it set up
  earlier now stops at the y/N for its own lock, which is the same
  question as for any lock it did not write this run; `--yes` answers
  it. `nix flake check` on a copy: green. The runbook follows: section 3
  says what `harness init` prints and asks before the first `direnv
  allow`, and the SELinux troubleshooting entry names `scripts/install.sh`
  as the one that labels the socket directory.
- First session in this checkout on the NixOS-WSL host, under the managed
  settings (231 deny rules, the strict allowlist, `/mnt/c` and `/run/WSL`
  hidden). The checkout and the copy brought over from the Windows side
  (`C:\code\claude-nix-harness`, placed beside it as
  `../wsl-build/claude-nix-harness`) are byte-identical, 63 files; the
  checkout's only extra is the generated `.claude/settings.json`. Branch
  `wsl-route`, the 2026-10-23 WSL route staged (9 files), nothing
  committed. `nix flake check` on a copy of the regular files (CLAUDE.md,
  "Checks"): 16 checks evaluated, every output already in the store from
  an earlier build; `hook-test` (252) and `project-settings-test` (23)
  forced with `--rebuild` and passed here. Learned about the hook from
  inside: a `jq` path into a settings file's `env` object was refused as
  a `.env` read (the secret-file pattern is `.env` followed by a
  non-alphanumeric), `ls /mnt/c/code` as a Windows executable, and a
  heredoc is read as part of the command, so a shell write of a document
  that mentions `.claude/` paths, `.env` or `sudo` is refused while the
  Edit tool, checked by path only, is not. All as designed; nothing to
  change. The host's `/etc/nixos` is still the one baseline commit
  `install-wsl.ps1` made and has no remote, so `wsl/update.sh` has nothing
  to pull, while the host repo moved on the same evening (nixos-unstable,
  `trusted-users = [ "root" ]`, `nixos/workbench.nix`); the host repo's
  business, noted because the next switch carries the change below.
- `/model` in a VS Code session on the host failed with `Failed to set
  model: EROFS: read-only file system, open
  '/nix/store/...-home-manager-files/.claude/settings.json.tmp.<id>'`.
  Cause: `home/default.nix` set
  `programs.claude-code.settings.worktree.baseRef`, the one key that made
  home-manager write `~/.claude/settings.json` as a store symlink, and
  Claude Code writes the user file itself at `/model`, through a temporary
  file beside the link's target. The key was redundant: the managed
  settings and the repo file carry `worktree.baseRef = "head"` from
  `lib/settings.nix`. The home module now enables the package only
  (staged); at the next switch home-manager removes the link and Claude
  Code creates a plain file on the first write. Nothing moves within a
  session's reach: the managed layer is immune to user settings and the
  settings body's `denyWrite` covers `~/.claude`. The unmanaged host was
  never affected, `harness bootstrap` writes that file as plain JSON. No
  generation activated from the session (handoff rule); the host repo's
  `check-access.sh` case "HM settings.json is a store symlink" inverts
  once it is.

## 2026-10-23

- Native NixOS recorded as a tested host, unmanaged shape: the NixOS 26.11
  laptop runs harness repos, this checkout included, on the repo file
  alone, with direnv 2.38.2 (the `pkgs/direnv.nix` override), devenv 2.4.0
  and Claude Code 2.1.296 from its own home-manager configuration. The
  install script has never run there and the README now says not to: the
  bootstrap would write `/etc/nix/nix.conf`, a store symlink the next
  rebuild restores (roadmap gap A, the NixOS branch, stays open). The
  managed module has still not run on a live host. README reshaped for a
  first-time reader: one paragraph on what the harness does, then a route
  per host; the `harness check` case counts stay in this file.
- Later the same day, a session on the NixOS laptop worked the brief's
  seven items, every one proven by a flake check from the checkout
  (`nix flake check .`, 14 checks, green); the README and runbook lines
  above that said not to run the install script on NixOS are superseded
  by the NixOS branch below.
  - `harness init` ran the settings test with `/repo` literals against the
    real repo's file, so it died with "fails the harness checks" on any
    checkout. The test takes the repo root as an argument (default
    `/repo` for the flake fixtures), init passes the real path, and a
    fixture at `/home/acme/code/git/acme/demo` proves the test at a real
    path (`project-settings-root-test`, 23). How the 2026-10-22 Ubuntu init
    got past that check is not recorded.
  - Host detection (roadmap gap A, the NixOS half): NixOS is `/etc/NIXOS`
    or `ID=nixos` (the marker is invisible from inside a session, the
    os-release line is not), WSL is the binfmt `WSLInterop` file or
    `WSL_DISTRO_NAME`. `root_write` refuses any target that resolves into
    `/nix/store` whether or not NixOS was detected, naming the
    `nix.settings` or `boot.kernel.sysctl` option instead. On NixOS the
    install script downloads nothing and bootstrap implies `--no-root`:
    the `nix.settings` block is printed when `nix.conf` lacks flakes or
    the devenv cache, the sysctl as a `boot.kernel.sysctl` line, and every
    user file that is a store symlink (home-manager's) is left alone with
    its option printed. Doctor opens with a host line (`host: NixOS 26.11
    (Zokor) ..., 3 home-manager owned files skipped`, `host: WSL2 (Ubuntu
    24.04)`) and reports home-manager files as ok. `harness init` on a WSL
    host uncomments `platform = "wsl"` in the generated `devenv.nix`.
    Stubs only (install-test 60, harness-bootstrap-test 151,
    harness-doctor-test 29, harness-init-dry-run-test 31); on this laptop
    `harness doctor` and `bootstrap --dry-run` print the NixOS lines and
    call no sudo. Live WSL, the `[boot] systemd=true` check and the
    `environment.d` skip stay open.
  - `nh os switch|boot|test` and `nh home switch` denied by rule and by
    the hook; `--add-dir` joins the nested-`claude` flags (hook-test 252,
    scoped 279, worktree 271). `nixos-rebuild` stays denied whole.
  - The env-file preamble was fail-open: `direnv export` errors were
    discarded and the command ran without the repo's environment. The hook
    now ends every Bash decision with `check_env`: `direnv status --json`
    (3 ms) refuses a blocked or denied `.envrc`; otherwise `direnv export
    json` runs with direnv's state variables unset, and a non-zero exit or
    an `is blocked` line refuses the command with the first error line and
    the fix. A good export is remembered under
    `~/.cache/claude-nix-harness/direnv-ok` by the mtimes of `.envrc`,
    `devenv.*`, the direnv and devenv binaries and the DEVENV_PROFILE path,
    because the export costs 0.2 s warm and seconds after a change (4.5 s
    on this checkout): a steady-state Bash call now costs 36 to 41 ms in
    the hook, 26 ms without an `.envrc`. `require_allowed` does not fail
    the load: an edited, unapproved `devenv.nix` exports with
    `DIRENV_REQUIRED` set and passes this check.
  - `harness check` judged verdicts on every string in the transcript, the
    model's prose included. Verdicts now see tool results only; the
    upstream-refusal patterns still read everything, since they can only
    make a case inconclusive. `harness check --parse <jsonl>` prints what
    the verdicts see; `check-parser-test` (9) runs it over two fixtures,
    one where the prose claims a denial the tool result refutes.
  - Ubuntu user namespaces: where AppArmor confines them, bootstrap
    writes `/etc/apparmor.d/bwrap` (the profile from the Claude Code
    sandboxing docs, marker line first) and reloads AppArmor instead of
    flipping the machine-wide sysctl; `reset` removes it; doctor says
    whether the profile is there and warns when `bwrap` on PATH is not
    `/usr/bin/bwrap`. The `unprivileged_userns_clone` sysctl path stays
    for older Debian kernels. Stubs only; the Ubuntu laptop verifies it.
  - The NixOS module evaluates in `nix flake check`:
    `nixos-module-eval` forces only the `/etc/claude-code` tree of a
    `nixosSystem` with `harness.enable` and asserts the sandbox block, the
    hook path and the deny rules; `nixos-module-assertion` reads
    `config.assertions` with `allowUserNamespaces = false` and finds the
    module's message, no toplevel built. `examples/nixos-host.nix` is the
    import snippet. No generation was activated.
- Later the same day, from the Windows laptop: the Windows route and the
  first live managed host, NixOS-WSL 2605.7.2 (NixOS 26.05) on Windows 11
  Home 26H2 with WSL 3.0.3 (kernel 6.18). `scripts/install-wsl.ps1`, run
  from a checkout on Windows, resolves the latest NixOS-WSL release,
  verifies the published sha256, registers the distro, and inside it
  `scripts/wsl/bootstrap.sh` makes `/etc/nixos` a git checkout of the
  host's nixos-config flake (a URL, or a Windows folder with one baseline
  commit), builds `nixosConfigurations.<name>` as the checkout's owner and
  activates as root; later runs go through `scripts/wsl/update.sh`: `git
  pull --ff-only`, build, switch, never a commit on the box. `-NoSwitch`
  builds and prints the activation for a host where the human switches.
  `examples/nixos-wsl-host.nix` is the host file, `scripts/wsl/verify.sh`
  the check (19 cases: DNS and HTTPS, flakes and the devenv cache, the
  managed tree, strict allowlist and hook, user namespaces, bwrap, socat,
  direnv, devenv, ccmux, claude and git on PATH, the session variables
  and direnv hook in a login shell, the Windows PATH kept off). The host
  switched to the harness through that route and passed all 19; `harness
  check` has not run there yet. Learned: Nix's libgit2 refuses a checkout
  owned by another user, hence build as the owner, activate as root; the
  home module leaves the shell to the host, so without
  `programs.bash.enable` in home-manager neither the direnv hook nor
  `HARNESS_EXPECT_MANAGED` reach a terminal; NixOS-WSL masks
  `firewall.service`, so the open system runs no Linux firewall and the
  Hyper-V firewall is the one in effect; mirrored networking policy-routes
  every 127.0.0.1 packet through `loopback0` and Windows, so an nftables
  firewall there must trust `loopback0`, and a resolver on 127.0.0.53
  needs `ip rule add to 127.0.0.1 from 127.0.0.53 lookup local` or its
  replies vanish. A host-wide dnsmasq, squid and nftables egress filter
  was built and verified on the same box first, then set aside: the
  sandbox's strict allowlist already covers sessions, and it stays out of
  this repository.
  - The host's first shell entry in this checkout failed: nixos-26.05 ships
    devenv 2.1.2, whose direnvrc dies with `structuredAttrs: command not
    found` on 26.05's structured-attrs dev shells, while the home module
    takes `pkgs.devenv` from the host's nixpkgs. With this flake's pinned
    devenv 2.4.0 first on PATH the same entry succeeded in 13 s and wrote
    the repo file (sandbox on, 7 hooks, 248 deny rules).
    The host now tracks nixos-unstable, the branch this flake is built
    against, which carries devenv 2.4.x; `examples/nixos-wsl-host.nix` says
    so and keeps, commented, the fallback for a stable-branch host (overlay
    `devenv` from `inputs.harness.packages` and drop `inputs.nixpkgs.follows`
    on the harness input, which also built). The README's "Usage" snippet
    with `follows` is right only where the host's nixpkgs is at least as new
    as this flake's.
    Also checked on that host (`check-access.sh` in the host repo, 22 of
    23): home-manager's store symlinks (`~/.claude/settings.json`,
    `~/.bashrc`, direnv config) with `~/.claude` writable, `systemd --user`
    up for uid 1000, bwrap with `--unshare-all`, a private network
    namespace and a tmpfs over `/mnt/c` as the user, `/mnt/c` honouring
    chmod under `metadata`, `/etc/claude-code` root-owned and unwritable.

## 2026-10-22

- Audit follow-ups 0.4 and 0.5 (roadmap). `CLAUDE.md` now says how to run
  the flake checks from inside a session: a copy of the regular files,
  then `nix flake check path:<dir>`. The `git archive` advice was wrong
  twice over: the archive misses untracked files, and `path:` on the
  checkout itself fails because the sandbox masks the untracked dotfiles
  (`.bash_profile`, `.vscode`, ...) as device nodes, which the fetcher
  refuses (found when the hook-test build for the case 2 fix hit
  `.bash_profile`). `tests/harness-bootstrap-test.sh` runs the harness
  with the stub directory as the whole PATH; the by-hand run on a host
  with `getenforce` or `code` used to fail 34 cases. By hand on the
  Ubuntu laptop it then failed 52 others: the bootstrap's `nix_path`
  sources the nix-installer's profile.d, which puts the default profile's
  real nix ahead of the stub, and the real nix wanted GitHub for the ref
  (on Fedora the same file adds directories without a nix in them, which
  is why the 2026-10-21 measurement passed). The profile.d files it
  sources are now `HARNESS_NIX_PROFILE_D`, which the test sets empty. By
  hand from inside a session and in the flake check: 104 of 104.
- Case 2 of `harness check` again on the Ubuntu laptop, now with the scrub
  key gone: the probe ran, `DEVENV_ROOT` was empty, and the two diagnose
  sessions showed why. devenv 2.4.0 creates `$XDG_RUNTIME_DIR/devenv-<hash>`
  before it evaluates, the sandbox mounts `/run/user/<uid>` read-only, so
  every `direnv export` inside the sandbox failed, and direnv keeps a failed
  load (`DIRENV_DIR` set, nothing exported) until a watched file changes.
  Reproduced in a session on the checkout: with `XDG_RUNTIME_DIR` set to the
  sandbox's `TMPDIR` for the direnv process alone, the same evaluation
  exported `DEVENV_ROOT` and a runtime directory under `/tmp/claude-1000`;
  `DEVENV_RUNTIME` is ignored by devenv. The hook's preamble now does that
  (hook-test, one more assertion). Why it never showed before: most likely
  the earlier hosts had no systemd user session, so `XDG_RUNTIME_DIR` was
  unset and devenv fell back to the temp directory. Noted, not decided:
  this is the fifth workaround for evaluating devenv inside the sandbox per
  command (direnv and devenv on PATH by store path, the two cache write
  entries, `devenv.local.*` out of the literal deny list, the `shell-*.sh`
  litter, this); the SessionStart hook runs outside the sandbox and could
  evaluate once and write the exports into the env file instead. A dated
  roadmap entry reopens decision 7.3 if that is wanted; the roadmap's open
  question on the evaluation cost carries the note. The run after the fix,
  from a fresh terminal: 12 of 12, the first full pass of the twelve cases
  (roadmap item 0.9 closed).
- `harness upgrade` hands the user steps to the upgraded harness: after the
  profile upgrade it execs the profile's new wrapper as `bootstrap --no-root
  --no-profile` with the original flags, when that wrapper's store path
  differs from its own (`HARNESS_SELF`, exported by the wrapper). The
  running process is the old build, and its user steps are the old ones:
  the same morning, `harness upgrade` to the build that removes the scrub
  key wrote the key back, and the `harness check` after it failed the same
  five cases. harness-bootstrap-test 102 to 104.
- First `harness check` on the checkout (Ubuntu 26.10, from a terminal; the
  first run of cases 11 and 12 anywhere): 9 of 12 passed, and the three
  failures were two findings and one test bug. (1) The per-command devenv
  shell had not loaded inside the sandbox since 2026-10-21: a literal
  `denyWrite` path is masked as an unreadable device node whether or not
  the file exists, devenv reads `devenv.local.yaml` when it exists, so
  listing `devenv.local.*` there made every evaluation fail with
  "Permission denied" (`DEVENV_ROOT` empty, case 2). The two are out of the
  literal list and stay in the hook's refusals; the `**/` globs keep them
  for macOS. This also answers roadmap item 2.5: `.envrc`, `devenv.nix`
  and `devenv.yaml` can never be literal entries, direnv and devenv must
  read them. (2) `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` in the repo file is
  ignored: the debug log says "project-scoped settings can't set this key"
  and `DB_PASSWORD` reached the shell (case 12; the GitHub token deny
  entry held). Moved to user scope through the bootstrap, it did worse:
  every later check run lost 4 to 5 cases to Claude Code's own permission
  layer ("a variable in this command can't be checked before it runs",
  grep on `/proc` "blocked: only the working directories", a write under
  `~/.claude` "a sensitive file", `mkdir` plainly "denied"), which a `-p`
  session cannot answer. Six session logs, three with the key and three
  without, differ at startup in exactly one line, `settingsEnv keys:
  CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` against `none`: with the key, 2.1.300
  no longer auto-allows sandboxed Bash commands and runs its static path
  analysis on every one. Interactively that is a prompt on every command
  with a variable. The scrub is out everywhere (repo, managed, bootstrap,
  doctor; the bootstrap removes the copy it wrote); what strips secrets is
  the explicit `credentials.envVars` deny list, and case 12 now asserts
  that (`env-deny`: both GitHub tokens). The wrong turn cost one round:
  the "without the key" experiment ran after a `harness upgrade`, which
  re-ran the bootstrap that wrote the key back. (3) Case 11's probe got
  "File exists" from the mask, which is the deny working; the case accepts
  that when the host has no such path. Also learned: a `-p` permission
  refusal matched `denied` and passed two cases; the check now counts
  every such refusal as inconclusive, prints it, and keeps a debug log per
  case (`<name>.debug.txt`), where the decision lives. project-settings-test
  22 to 23 (fenced 24), harness-bootstrap-test 101 to 102. Still
  unverified: case 2 (the devenv shell inside the sandbox) and the rest of
  the list on a host without the key; every run after the fix had it. Also
  that day: `harness init` on the checkout from a terminal, and `ccmux` on
  it.
- First real Ubuntu run (26.10, the test laptop; roadmap gap B).
  `scripts/install.sh --code-root ~/Code` installed Nix, bootstrap wrote
  every user file and flipped `kernel.apparmor_restrict_unprivileged_userns`
  on request. Found: bootstrap exits 1 on any MISSING line, and `set -e`
  in install.sh then skipped `harness init` on the checkout without a
  word; the two missing tools (tmux, claude) are the ones that shell
  provides. install.sh now runs init anyway and keeps bootstrap's exit
  code (install-test 44 to 47). Also seen: a `path:` harness ref reports
  `harness: dirty` in the receipt, since a path flake carries no git
  revision; cosmetic. Pre-install, by hand (the hook refuses them from a
  session): the checkout's `devenv.nix` and `devenv/devenv.nix` edits
  listed under 2026-10-21.

## 2026-10-21

- Hook: `git checkout <ref> <path>...` is refused (roadmap item 0.7);
  `-b`, `-t`, `--track` and `--orphan` with a start point pass, one-word
  `git checkout <path>` stays open (runbook section 8). hook-test 233 to
  241. `devenv/devenv.nix` imports `pkgs/direnv.nix` like `flake.nix`
  (item 0.2). The checkout's own `devenv.nix` and the `harness init`
  template list every harness option, commented out; the checkout turns
  `allowMemoryEdits` on. Learned: the rendered hook runs the suite on a
  host without Nix with bash, jq and sed alone; only the store-path direnv
  case needs the built hook.
- Decided: one installer. `scripts/install.sh` owns every root and
  pre-Nix step and `harness bootstrap` the user side, so the Fedora root
  steps leave bootstrap (roadmap item 0.3). The target flow (installer,
  the checkout as command center, `harness init` per project, `ccmux`
  sessions that propose what they are refused) is written down in the
  roadmap with its gaps: NixOS and WSL detection, a real Ubuntu run, a
  devenv guide for non-Nix users, the tier split.
- Whole-repo audit, twice (Opus, then Fable), every hook claim re-run
  against the built hook; of the 13 findings, three idle sessions fixed
  eleven the same evening, staged for review (roadmap Done; the rest and
  what turned up are roadmap item 0).
  What the hook missed: `git checkout .`, `checkout -f`, `switch -f` and
  `--discard-changes`, `branch -f`, `tag -f`, `switch -C` and `checkout -B`
  (the normaliser lowercases, so these needed a case-preserving copy of
  the command, `nc`, from which `n` is now derived), `worktree remove -f`;
  an Edit through a symlink in the repo (`realpath -s` kept the link, so a
  link to `~/.bashrc` or `~/.claude/settings.json` was editable; the edit
  cases now run on the resolved path too, as one function); `~/.bashrc.d`
  and `~/.local/bin`; `file -b -f X` and `file --files-from X`, which
  print each line of X; and three credential files that no layer hid:
  `~/.aws`, `~/.config/gh`, `~/.git-credentials`, the last two being the
  push credential the "agents never push" design assumed absent. All are
  `denyRead`, `cred_files` and deny-rule entries now. hook-test 204 to
  233, project-settings-test 21 to 22. `harness init` on an existing repo
  approved and ran its `devenv.nix`, `.envrc` and `devenv.local.*` unread;
  it prints them and asks (`--yes` answers, no terminal refuses).
  `harness upgrade` builds the new package before removing the old entry.
  The no-receipt `reset` branch and the profile-ccmux ref fallback are
  gone: no receipt means nothing to undo. harness-bootstrap-test 94 to
  101, init 19 to 24. `lib/project-settings.nix` deleted (a pass-through),
  the direnv version check written once (`pkgs/direnv.nix`), the generated
  settings byte-identical. Learned: the tree-copy recipe needs a
  regular-file filter, the sandbox masks untracked dotfiles as device
  nodes; `harness-bootstrap-test` run outside the Nix sandbox on this host
  fails 29 cases (it assumes no `getenforce` or `code` on PATH), so the
  check derivation is the number that counts. Left on the board: 9 (the
  Fedora root steps in two files, a decision), 13 (`~/.kube`, `~/.docker`,
  not planned), and the `devenv/devenv.nix` half of 10, applied by hand.
- Broker mod, first validate and test run, by hand on the built mod
  (`nix build .#harness-broker`, `claude plugin validate --strict result`,
  `claude plugin test result`): validate passes, 5 tests pass. Strict
  validate fails a manifest with no `author`, so `mkMod` takes `author` and
  writes `author.name`; the broker's is `claude-nix-harness`, the
  marketplace owner. Learned from the first test run: a test's `$` raises
  events only (`session.start`, `session.end`, `command.run`); the plugin's
  own calls (`$.session.id`, `$.store`, `$.clock`, `$.command.register`,
  `$.ui.status`) are answered by the test's `on` hooks, with `mock.store`,
  `mock.clock` and `mock.env` for three of them, and the test cannot make
  them itself. The three cases that read the store back through `$` were
  replaced by five that read `/fleet` and what the plugin handed those
  hooks: two sessions on one machine (the other's row seeded in the store)
  both listed, an ending session removing only its own row, the tier in the
  status line, a session started by hand, an empty store.
  `tests/mod-validate-test.sh` over `managed-mods` then failed the same
  way on the marketplace manifest: strict validate wants a top-level
  `description` (where the official and ponytail marketplaces keep it, not
  under `metadata`), so `mkMarketplace` takes `description`; rerun, it
  ends `mod-validate-test: ok` (marketplace and mod validate, 5 tests
  pass). Not run yet: a load on a managed host. Decided the same day: no Node in
  the devenv. The `node: command not found` SessionStart error came from
  the ponytail plugin's hook, a personal plugin; the host has no Node at
  all, and a runtime on every agent's PATH for one optional plugin is not
  the harness's to ship. A repo that needs JavaScript adds it in its own
  `devenv.nix`.
- Broker mod groundwork, roadmap item 8 started out of order: only stage C
  (the gate) depends on the tier split; the builder, the registration keys
  and the observe slice depend on nothing above it. `lib/mods.nix`: `mkMod`
  writes the manifest from Nix attributes, so the checkout holds no
  `.claude-plugin` (the deny rules keep an agent out of one, `harness init`
  refuses one under `.claude`); `mkMarketplace` lists each mod by relative
  path, which is what makes it the organisation's under the guard.
  `mods/harness-broker`: the first slice of stage A, a row per session in
  `$.store`, the tier in the status line, `/fleet`; three `claude plugin
  test` cases. `harness.mods` on the NixOS module; when a mod is listed the
  managed settings carry `extraKnownMarketplaces.harness` (a `directory`
  source by absolute path) and `enabledPlugins."<mod>@harness"`, shapes from
  the marketplace, org and mods admin pages, the org page saying the managed
  file alone registers and installs. `packages.managed` is unchanged until
  `harness.mods` is set; `managed-mods` is the tree with the broker.
  `managed-tree-test` (12 checks) in `nix flake check`.
  `tests/mod-validate-test.sh` (`claude plugin validate --strict` and
  `claude plugin test` over the built tree) is a check only where unfree
  packages are allowed, claude-code being unfree in nixpkgs, and has not been
  run: an agent's session cannot run `claude plugin`, so the validate loop
  (`mods/harness-broker/README.md`) is the human's. Nothing has run on a
  managed host.
- One install route, roadmap item 0 decided: the root `install.sh` (any
  Linux, stub-tested, never run on a distro) folded into
  `scripts/install.sh` + `harness bootstrap` (Fedora, run end to end) and
  removed. The script keeps the Fedora route and gains the root script's
  nix-installer route for every other Linux (downloaded to a file first;
  `--yes` passes `--no-confirm`, and is required when piped into bash with
  no terminal), defaults the ref to the checkout it runs from (the
  runbook's `HARNESS_REF=path:$PWD` is no longer needed) and ends with
  `harness init` on that checkout, the root script's shell build and
  self-check; the root `.gitignore` carries the three lines init ensures,
  so the run leaves the tree clean. bootstrap: the Fedora-only preflight
  is gone (Fedora 44 or newer is the dnf route, anything else the
  installer's; SELinux steps only where the tools exist, the socket step
  only where the unit exists); the user-namespace sysctl, offered on its
  own, `--yes` answering it, a decline printed at the end and kept in
  doctor's report; the direnv hook wired into a `~/.bashrc` that does not
  source `~/.bashrc.d` (Fedora's stock one does) and into `~/.zshrc`; the
  tmux block in the file tmux reads, since tmux stops at `~/.tmux.conf`
  when it exists and the old block in the XDG file never loaded there;
  `experimental-features` in the nix.conf block when no line outside it
  sets them. `reset` puts the sysctl back and runs `/nix/nix-installer
  uninstall` when the receipt says the script installed Nix. The system
  files bootstrap touches are overridable for the tests (`HARNESS_NIX_CONF`,
  `HARNESS_SYSCTL_DROPIN`, `HARNESS_NIX_INSTALLER`, `HARNESS_OS_RELEASE`,
  `HARNESS_CA_BUNDLE`). `install-test` rewritten (44 checks),
  `harness-bootstrap-test` new (94). Found by the new test: the doctor's
  `code` probe from earlier in the day ran before its `command -v` guard,
  which under bootstrap's errexit and pipefail ended a run on a host
  without VS Code with exit 127; fixed. Nothing run on a real non-Fedora
  host yet.
- Root `CLAUDE.md` (the day's roadmap item 1, now in Done): under 30 lines,
  which document owns what, the handoff's standing rules, the
  closed-decision rule, how a session runs the checks. First `harness
  doctor` and `harness init --dry-run` against the checkout, from inside a
  session. init: `devenv.yaml` and `devenv.nix` differ by design (this repo
  imports `./devenv`), `.envrc` and `.worktreeinclude` unchanged, the three
  `.gitignore` lines it would add are covered by `.claude/`. doctor: every
  host line ok, but the repo report called `.claude/settings.json` a plain
  file with no runnable hook, and the VS Code lines said mkhl.direnv was
  missing. Both false: the sandbox masks the repo's `.claude` files as
  character devices, and `code` dies before printing because the session's
  `LD_LIBRARY_PATH` carries a Nix alsa-lib path and the host binary then
  loads `librt` from the Nix glibc (`symbol lookup error`). doctor now says
  so, a warning each and no verdict; `harness-doctor-test` 27 checks. Where
  that variable comes from is open: not devenv, not direnv, not the harness.
  The bootstrap plan's boxes for tasks 1 to 5 are ticked; task 6 and the
  route decision stay open (roadmap item 0). Learned: the hook refuses a
  command that runs `git init`, `git add` or `git commit` on a scratch copy
  under `$TMPDIR` as well, so the flake check from a session is `git
  archive HEAD | tar -x` into a directory, then `nix flake check path:<dir>`
  (passed on `7cc5803` and on the working tree).
- Check of the day's commit (`ffe26ad`), fixes applied. The path-first
  credential rule had three ways through, each measured to print the file:
  a second line after a harmless verb (the normaliser folds newlines, so the
  raw command is now checked too), `>(cat ...)` process substitution (`(`
  joined the excluded characters) and the options that read file names from
  a file (`file -f`, `--files0-from`, `--pathspec-from-file`), whose errors
  echo each line; those are refused by name. `git checkout <ref> -- <path>`
  also caught `git checkout main && npm run build -- --watch`; the ref group
  now stops at `;`, `&` and `|`. Ten hook-test cases. Bootstrap appended
  the tmux block only when no marker was there, so the `HARNESS_PROJECT`
  unsets never reached a host bootstrapped earlier; the block is replaced
  when it differs, on bootstrap and upgrade. The FileChanged matcher gained
  `devenv.local.yaml`, which devenv's direnvrc watches. `scripts/install.sh`
  enables the daemon socket and its SELinux label again before `nix run`:
  the nix-daemon package installs the socket disabled (no Fedora preset),
  so the dnf-only version could not start bootstrap, which was to enable
  it; reset's summary now lists the socket and the direnv database it
  removes. Stale `ccode` and
  `--no-root` lines in the docs dropped; nixfmt, statix and deadnix clean
  over the whole tree (the root `devenv.nix` by hand, since the hook does
  not let a session edit it). Learned: inside a harnessed session `nix flake check` on
  the checkout fails, since Claude Code masks the absent `.gitmodules` as a
  device node and Nix's git fetcher cannot open it; run it on a `git
  archive` copy. `deadnix .` in the sandbox errors on the masked
  `devenv.local.nix` the same way.
- Ponytail audit of the tree, fixes applied the same day. The hook's
  credential rule is path-first: a command naming a secret file is refused
  unless it is one harmless verb (`ls`, `stat`, `file`, `du`, `wc`, `rm`,
  `git rm`, `test`, `echo`, `printf`, `touch`) with no pipe, `$(`, backtick
  or `<`; the reader-verb list is gone and `git checkout <ref> -- <file>`
  joined the git history rule (22 new hook-test cases). `devenv.local.nix`
  and `devenv.local.yaml` are in `repoProtected`: measured, an interpreter
  write of `devenv.local.nix` landed from inside the sandbox, and devenv
  imports that file with no `require_allowed` prompt, so the human's next
  shell would have run it; a literal `denyWrite` masks a missing path, so
  it cannot be created now. Bootstrap's pasted tmux block lacked the
  `HARNESS_PROJECT` unsets that `pkgs/tmux.conf` has (a pane for org B
  inherited A's project); bootstrap now appends the `pkgs/` files, handed
  over by `harness.nix`. `reset` without a receipt no longer lists Nix as
  its own. `scripts/install.sh` keeps only the dnf step and execs `harness
  bootstrap`, which does the other root steps. `ccode` removed;
  `install-test` takes the three files it reads, not the whole checkout.
  Not changed: `require_allowed devenv.local.nix` in the `.envrc` template,
  since direnv's behaviour on a file that does not exist is unverified.
- External review of four items (docs as cross-session state, the SSH
  threat model, operator config in `home/default.nix`, hook bypasses)
  checked against `0d586f5` and HEAD. Two described files this tree never
  had (`lib/mcp.nix`, `tests/env-guard-test.nix`, git identity in the home
  module); dropped. Measured here: the gcr agent socket answers from
  inside the sandbox at its guessed path and listed a plain ED25519 key
  next to the `-sk` one, so the laptop was out of its own README's spec;
  the reader and git forms now in `hook-test.sh` passed the hook (`dd`,
  `tr <`, bare redirection, `perl`, `git show HEAD:.env`, `git checkout
  <ref> -- .envrc`, interpreter writes to `.envrc`), while `git restore`
  and the readers added in `c3060bb` were blocked; the `Read(**/.env)` deny rules
  do fence `.env` under the checkout in the sandbox (bind-mounted as
  `/dev/null`), which the review had assumed nothing did. Into the
  roadmap: root `CLAUDE.md` (item 1), keyring `denyRead` plus a doctor
  warning, the worktrees `denyWrite`, `repoProtected` additions and the
  `core.hooksPath` live case (items 3.3 to 3.6), the path-first reader
  rule and the Edit-rule asymmetry (ideas). Left out: everything about
  operator identity in the home module, which never carried any.
- An issue draft for a "fleet" mod loaded through `prependPlugins` was
  checked against `docs/sessions.md` and the mods docs: it is the broker
  mod's stage A. What it got right and the design lacked is the loading
  shape: `strictKnownMarketplaces` registers nothing, a managed mod needs
  `extraKnownMarketplaces` plus `enabledPlugins`, and `prependPlugins`,
  once set, must name `sec-default@builtin` or the guard stops loading.
  Written into sessions.md section 5. Dropped from the draft: `$.fs` and
  `$.process` guards inside the mod (nothing else loads on a managed
  host), `DEVENV_ROOT` as the identity (the harness exports
  `HARNESS_TIER` and `HARNESS_PROJECT`), a separate `ccmux-centre` mod.
- Sandbox hardening, items 1, 2 and 4 of the roadmap's list: the bootstrap
  writes `sandbox.network.strictAllowlist = true` into the user-scope
  `~/.claude/settings.json` (merged with jq, reported by the host check,
  removed by the reset; `--no-account-sync` also turns `syncClaudeAiSkills`
  and `syncClaudeAiPlugins` off, default unchanged). The repo file carries
  its own protected paths as literal `denyWrite` entries under
  `config.devenv.root` (`repoRoot` in `lib/settings.nix`), since Linux
  skips the `**/` globs; confirmed regenerating the test repo's file. The
  settings body sets `env.CLAUDE_CODE_SUBPROCESS_ENV_SCRUB = "1"` (docs:
  strips credential-shaped variables from Bash commands, hooks and stdio
  MCP servers, keeps filesystem isolation on, PID namespace on Linux) and
  denies `GITHUB_TOKEN`, `GH_TOKEN` and the enterprise variants, which the
  scrub keeps on purpose. `project-settings-test` 18 checks; `live-check`
  cases 11 and 12 added, to be run from a terminal.
- One CLI: `scripts/bootstrap-fedora.sh`, `init-repo.sh` and `live-check.sh`
  became `harness bootstrap|upgrade|doctor|reset`, `harness init` and
  `harness check` (`nix run .#harness -- <command>`; `bootstrap` adds
  `harness` to the profile). `--check` is `doctor`, now also running
  `claude doctor` and, inside a repo, checking the settings symlink, the
  direnv approval and the hooks; every command takes `--dry-run` (never
  sudo), `--yes`, `--verbose`. `scripts/install.sh` (curl-able, under 100
  lines) does the root steps before Nix exists. `bootstrap` writes a
  receipt; `reset` and `upgrade` read it and fall back to the built-in
  lists without one. New checks `harness-doctor-test` and
  `harness-init-dry-run-test`. Built by an Opus worker from the roadmap's
  design; `reset` with a receipt also removes the dnf packages the
  bootstrap added (tmux, git-core, ...), the plan says so before asking.
- Read fence prototype, `harness.readFence` (off by default): live in the
  test repo through a temporary `devenv.local.nix`. First run: the home
  directory was hidden as intended but `DEVENV_ROOT` was unset, because
  `~/.nix-profile` is a symlink and allowed paths are mounted by their real
  path, so direnv fell off PATH. Fixed in the hook's preamble (direnv and
  devenv by store path, resolved by the hook outside the sandbox); second
  run: devenv shell loaded, `~/.bashrc` and `~/.config/Code` unreadable,
  `~/.claude/shell-snapshots` readable so the Bash tool works. The hook refused the first probe for
  naming the credentials file, as it should.
- Nix hygiene after the CLI landed: `pkgs/harness.nix` took the whole
  flake source as an input (`src = self`, for a store-path fallback ref),
  so every edit in the checkout rebuilt it and the fallback pointed at a
  path garbage collection removes; it now takes `./tests` only and falls
  back to `github:bilibo/claude-nix-harness`. New `formatter` output
  (`nixfmt-tree`), `nix fmt` clean; `statix` and `deadnix` leave two
  pre-existing style notes in `home/default.nix` and `pkgs/direnv.nix`.
- Verified against the Claude Code docs (env-vars, sandboxing, settings
  reference): the scrub variable and what it keeps, `credentials.envVars`
  `deny` from any scope with no built-in list, `strictAllowlist` ignored
  from project and local scope, only a `false` honoured for the two sync
  keys, `env` from the repo file after trust.

## 2026-10-20

- Unmanaged Fedora host: `scripts/bootstrap-fedora.sh` (Fedora 44's own
  `nix` and `nix-daemon` packages; direnv, devenv and ccmux from the
  flake's new `packages.direnv` and `packages.devenv`; the home module's
  configuration as plain files; `--check` as the host doctor; `--upgrade`;
  `--reset`), `scripts/init-repo.sh` (runbook section 3, including the two
  `direnv allow`s a new repo needs), `scripts/live-check.sh` (section 5's
  live cases, judged on transcripts and files).
- Two host findings, fixed in the bootstrap script: SELinux gives `/nix`
  `default_t` and the daemon socket directory needs `var_run_t`; Fedora 44
  has no legacy `ca-bundle.crt` paths, so `NIX_SSL_CERT_FILE` must name
  `/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem`.
- From zero on the Fedora laptop, end to end: `init-repo.sh raul/harness-test`
  wrote the repo file (settings checks and 154 hook cases passing),
  `nix flake check` passed on the host, `live-check.sh` 10/10 against `-p`
  sessions, with the hook, a permission rule and the sandbox each seen
  refusing. First time a real session ran on the repo file alone.
- Sandbox audit against the sandboxing docs and live: reads open except
  `denyRead`, glob `denyWrite` entries skipped on Linux (confirmed with a
  `mkdir` inside the sandbox), network prompt-gated without
  `strictAllowlist`, every unix socket reachable, environment inherited.
  Recorded in runbook section 8 and ordered in the roadmap.
- Account connectors off in harness repos: `disableClaudeAiConnectors`
  holds from the repo file (any scope), `harness.allowConnectors` opts a
  repo back in; `project-settings-test` asserts it (15 checks).
- Verified against the Claude Code docs (2.1.304): the Notification
  matcher names, FileChanged's literal-basename matcher, `--debug-file`,
  `claude doctor`, the scopes of `disableClaudeAiConnectors`,
  `syncClaudeAiSkills`, `syncClaudeAiPlugins`, `deniedMcpServers` and
  `blockReadsOutsideWorkingDirectories`.
- Installer survey (azd, Determinate nix-installer, rustup, uv) and the
  resulting design for one `harness` CLI: roadmap item 3.
- Docs reworked to the Fedora reality: README opening, host table, a
  "Lockdown level today" table; runbook sections 3 to 6 and 8; the
  handoff's inventory; this file.
- First cross-session case live: an org session's refused edit to
  `devenv/devenv.nix` relayed as a diff to the platform session, which
  asked Raul before applying. Written up as `docs/sessions.md`: identity
  from the host, the human as the only gate, a proposal flow, and the
  broker mod in three stages (observe, propose, gate); roadmap item 9
  reworded to match.

## 2026-10-18

- Repo-only shape: one settings body for the managed and the repo copy,
  the devenv module writes hooks and sandbox too, the hook blocks
  `settings.local.json` changes and nested `claude` launch flags,
  `project-settings-test` in `nix flake check`. An unmanaged host needs no
  host modules; the managed layer is the managed-host shape.
- `ccmux` replaces `ccode` (the old name stays as a second entry point).
- `docs/handoff-tiers.md` written from an inventory of this repo,
  `~/nixos-config` and the Claude Code 2.1.296 docs.

## 2026-10-17

- Own repo with a `flake.nix` exporting `nixosModules.harness`,
  `homeModules.harness`, `lib`, the managed trees as packages and the tests
  as `checks`.
- Verified against a real project repo (Azure Functions, Rust).
- Hook gaps compared with Hermes Agent, Codex, destructive_command_guard
  and codex-protect; the text-matching gaps accepted and listed in runbook
  section 8.
