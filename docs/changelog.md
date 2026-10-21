# Changelog

Dated entries, newest first. The roadmap says what is next; this says what
happened and what was learned on the day.

## 2026-10-21

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
