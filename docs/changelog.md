# Changelog

Dated entries, newest first. The roadmap says what is next; this says what
happened and what was learned on the day.

## 2026-10-22

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
  entry held). It moves to the managed copy and to the user-scope keys
  `harness bootstrap` writes; `harness doctor` reports it. (3) Case 11's
  probe got "File exists" from the mask, which is the deny working; the
  case accepts that when the host has no such path. project-settings-test
  22 to 23 (fenced 24), harness-bootstrap-test 101 to 102. Also that day:
  `harness init` on the checkout from a terminal, and `ccmux` on it.
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
  `HARNESS_PROJECT` unsets that `pkgs/tmux.conf` has (a pane for customer B
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
- First cross-session case live: a customer session's refused edit to
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
