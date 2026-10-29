# Task list: sprint to release

Working list, written 2026-10-28 late evening, for the morning of
2026-10-29. The roadmap still owns what is next in order; this is the
short form of what is in flight, with the live state of the host. Delete
it when the sprint is done or fold what is left into the roadmap.

## Where things stand (2026-10-28, end of day)

Host nixos-wsl, bootstrapped today for the first time, workers
`w-acme` and `w-globex`, jail `acme/infra` created under `w-acme`.

- `verify.sh`: 37 ok. `aj doctor` as owner and as `w-acme`: 0 missing.
- `ajmux -n acme/infra` hands over; `w-acme` is refused `globex/other`.
- ai-jailer commits today: `d35a481` (bootstrap skips on NixOS, doctor's
  owner-home check, staleness note), `955fe68` (md lint), `2316aa1`
  (the worker-upgrade fix: `aj upgrade --workers` runs `upgrade` as
  each worker; applied live, both workers' `aj` moved).
- **Staged, uncommitted** in ai-jailer: `tests/hook-test.sh` (the cwd
  default that made `aj init` fail as a worker) and its changelog bullet.
- nixos-wsl: `homeMode = "700"`, the `switch-to-configuration` exit
  status in `bootstrap.sh`, `verify.sh` (700 only; ai-jailer lock drift
  check). Committed as `4d1ee03`, pushed (main is level with origin).
- Owner-side cleanup done: no nix profile, no `~/.bashrc` block, no dead
  direnv/environment.d/Code files. The workers still have theirs from
  the first bootstrap (harmless duplicates).

## 0. State after the 2026-10-29 morning run

Sections 1, 2, 3, 6.1 to 6.5 and the rename are done in the working
tree (23 files, nothing committed; `nix flake check` passes on the
tree, 2026-10-29). The new rules are applied live: `aj upgrade
--no-profile --workers acme,globex` ran, `w-acme`'s `aj init acme/infra`
is 443/443, `verify.sh` 37 ok. Release = a tag on `main` with the README
true (decided 2026-10-29); the nixos-wsl `install-wsl.ps1` run from
scratch is a later item. `docs/changelog.md` has the day's entry; the
roadmap has V15 and the Read-deny answer.

New today, not in the list before: `aj check` has a login pre-flight
(the first live run as `w-acme` was 16 "no line matched" failures from
one missing login); the factory has `.ignore` with `devenv.lock`.

### Human steps left on the live gate (the session cannot do these)

- [x] V13: passes, 2026-10-29 afternoon: `aj check: 17 passed, 0 failed,
      1 skipped` as `w-acme` (the skip is tmux-display outside tmux). The
      login form that prompts once is `claude auth login`; `claude /login`
      on a first launch prompts twice (onboarding, then the command).
      Expect: no `FAIL  login`, and the cases pass (the `sandbox`,
      `cred-read`, `sudo-text`, `home-fence` lines are the ones that
      prove the jail). Paste the summary line into roadmap item 14.
- [x] V14 passes, 2026-10-29 afternoon (roadmap item 14 has the transcript).
      As run, as `w-acme`:
      `sudo -u w-acme -i sh -c 'cp ~/.claude/settings.json /tmp/s.bak && jq "del(.permissions.deny[0])" /tmp/s.bak > ~/.claude/settings.json'`,
      then `sudo -u w-acme -i sh -c 'cd ~/code/git/acme/infra && claude -p "run pwd" 2>&1 | tail -3'`.
      Expect `env-guard: worker without a jail: ... differs from ... (aj bootstrap rewrites it ...)`.
      Repair: `sudo -u w-acme -i aj bootstrap --no-root --yes` (what the
      owner's `aj upgrade --workers` runs per worker); rerun the `claude -p`,
      expect a normal answer. `aj doctor` as the worker says
      `the jail in ~/.claude/settings.json differs from` while broken.
- [x] V4 passes, 2026-10-29 evening: `ajmux acme/infra` in one tab,
      `sudo -u w-acme -i tmux attach -t acme-infra` in a second tab as
      `nixos`, both show the same pane. The fallback is closed too: the
      socket dir `/tmp/tmux-1001` is 0700 `w-acme`, `ls` and
      `tmux -S /tmp/tmux-1001/default ls` are denied to the owner. The
      owner attaches by becoming the worker, nothing is shared.
- [x] V5 passes, same evening: the pane's environment (`/proc/<pane_pid>/environ`)
      carries `XDG_RUNTIME_DIR=/run/user/1001` and `TMUX=`, no
      `DIRENV_*`; `/run/user/1001` exists with linger. The tmux session
      environment does not list it (`show-environment` says unknown
      variable), which is expected: only `update-environment` names live
      there.
- [x] V7 passes, same evening: `ls /home/nixos` and `ls /home/w-globex`
      as `w-acme` are denied; the owner lists the worker's repo.
- [x] V9, same evening: `claude -p "say ok" --debug-file` as `w-acme`
      logs skills loaded from `managed=/etc/claude-code/.claude/skills,
      user=~/.claude/skills, project=[]`, no sync line, and
      `~/.claude/skills` does not exist. As far as the log shows, the
      key is honoured.
- [x] V2 baseline, same evening: with the cell's `extraAllowedDomains`
      unset, `claude -p` running `curl -sI https://dev.azure.com` got
      `HTTP/1.1 403 user denied` from the sandbox proxy, no prompt, and
      the session proposed a `devenv.nix` diff. V2 and V3 done from a
      session the same evening, the cell's `devenv.nix` edited and
      restored as the worker: `dev.azure.com` listed is tunnelled while
      `example.org` is denied; `"*"` tunnels `example.org`. V1 passed
      too (`NoNewPrivs: 1` in a bare directory). Roadmap item 11 has the
      lines.
- [x] **Found during V4, 2026-10-29 16:55** (fixed the same evening,
      option (a), five checks pass; applied live by Raul with `aj upgrade
      --no-profile --workers acme,globex`, 0 missing; `aj check` as
      `w-acme` after it: 18 passed, 0 failed, 1 skipped): the interactive claude in the
      `ajmux` session wrote `permissions.defaultMode: "auto"` (plus
      `theme`, `tui`) into `w-acme`'s `~/.claude/settings.json`. The jail
      pins `defaultMode: "default"`, so the hook's `permissions`
      comparison failed and every Bash call of the worker was refused
      (V14's message) until `aj bootstrap --no-root --yes` as the worker
      rewrote it (done from a session at 17:10; doctor 0 missing). A
      mode switch in the TUI is a normal action, so this will recur.
      Decide: (a) let Claude Code own `permissions.defaultMode`: drop it
      from `jailBody` in `lib/settings.nix`, compare `permissions` with
      `defaultMode` removed on both sides in the hook's `jail_check`,
      bootstrap's write check (`pkgs/aj/bootstrap.sh` ~836) and doctor
      (~1252), two hook-test cases (defaultMode differs: 0; an added
      `permissions.allow`: still 2); or (b) keep the pin and document
      that a worker must not switch modes. Deny rules, the hook and the
      sandbox bind in every mode; `disableBypassPermissionsMode` stays
      compared either way.
- [x] The three managed-only keys (roadmap item 14, last box): bypass
      mode off, `allowManagedHooksOnly`, the mod policy; each a yes/no
      from you, then a dated roadmap line. Bypass mode: kept, verified
      2026-10-29 evening (`docs/verified.md`). The other two, with the
      docs read (roadmap item 14 has the detail): hooks run outside the
      sandbox and deny rules do not cover them, so `allowManagedHooksOnly`
      is the jail's wall against an extra hook, keep; `allowManagedModsOnly`
      is exactly "no JavaScript", keep; plugins are blocked by
      `strictKnownMarketplaces = []`, so list the marketplaces in
      `host.nix` to allow them (the official one is
      `{ source = "github"; repo = "anthropics/claude-plugins-official"; }`,
      and a machine that once ran under `[]` registers it again only
      through an `extraKnownMarketplaces` entry). Decided 2026-10-29 late
      evening: all three stay; plugins per host later (roadmap item 14).
- [x] New, 2026-10-29 evening: MCP and LSP servers run outside the
      sandbox and nothing in the law restricts them; `.mcp.json` is not
      a protected path (roadmap item 14, last box). Accepted as is the
      same evening: setting up an MCP server is a valid use of a cell.
- [x] The `.terraform` Read rule: dropped 2026-10-29 evening (roadmap
      item 14 has the line; `managed-tree-test` asserts the absence).
- [x] Review the diff, commit, push (`c1e9b69`, 2026-10-29 13:06).
- [x] In `/etc/nixos`: `nix flake update ai-jailer && nh os switch`
      done 2026-10-29 evening; `verify.sh` 37 ok, 0 failed. The README
      verify-table line is in `8ccdce0`; the lock commit `4fd920b` is
      pushed (origin main level, 2026-10-29 evening).
- [x] Roadmap item 11's V1 to V9: all nine closed 2026-10-29 evening,
      each box carries its result.

## 1. Close today's loop (15 min)

- [x] ai-jailer: commit the staged hook-test fix.
- [x] In the checkout shell: `direnv reload`, then
      `aj upgrade --no-profile --workers acme,globex`.
- [x] `sudo -u w-acme -i aj init acme/infra --yes`: idempotent; must end
      with the `ajmux -n` note and "Ready", hook-test 443/443.
- [x] Run the DAC and linger lines that were never pasted:
      `sudo -u w-acme -i sh -c 'ls /home/nixos'` (denied),
      `sudo -u w-acme -i sh -c 'ls /home/w-globex'` (denied),
      `sudo -u w-acme -i sh -c 'test -d /run/user/$(id -u) && echo linger ok'`.

## 2. Two validated bootstrap fixes (1 h, with tests)

Both checked against the code on 2026-10-28; see the chat's verdict.

- [x] Bare `aj upgrade` loads `.root.workers[]` from the receipt into
      `WORKERS` when none were passed and `--no-root` is off
      (`pkgs/aj/bootstrap.sh`, the `upgrade` branch of the dispatch).
      README line 234 already promises this. Test: bare `upgrade` after
      a `--workers` bootstrap runs `upgrade` as each worker. Decide: a
      receipt worker the host lacks gets `useradd` again on every
      upgrade (what doctor tells the operator to do anyway).
- [x] `useradd -s "$(command -v bash)"` instead of `/bin/bash`, and
      `true` instead of `/bin/true` in doctor's bwrap probe. Real on plain
      NixOS (only `/bin/sh` there); moot on NixOS-WSL, which links
      `/bin/bash` and `/bin/true` itself. Test 20's exact `useradd` line
      in `tests/aj-bootstrap-test.sh` changes with it.

## 3. Small wording fixes seen today (20 min)

- [x] The per-worker `warn the ai-jailer ref is this aj's store path …
      a later upgrade cannot move it` is misleading: an owner-side
      `aj upgrade --workers` prefetches a fresh snapshot and does move
      it. Only a worker upgrading on its own cannot.
- [x] The "Next: open a new terminal (PATH and NIX_SSL_CERT_FILE come
      from profile.d and ~/.bashrc.d)" trailer is stale on NixOS, where
      bootstrap writes neither.
- [x] `verify.sh` in nixos-wsl: nothing pending; the README there could
      name the new lock-drift check in its verify table.

## 4. Live verification still open in the roadmap (the release gate)

Item 14's gate, from `docs/roadmap.md` "The first live run": V12 to
V15, plus V1 to V9 of item 11 and V10, V11 of item 13 as narrowed. Run
them in `acme/infra` as `w-acme`, paste results into the roadmap's
boxes, tick what passes.

- [x] V13: a worker session starts, `aj check` passes as `w-acme`
      (API calls; the first live `aj check` transcript is V8).
- [x] V14: edit `~/.claude/settings.json` as the worker (drop a deny
      rule): every tool refused with the hook's `differs from` message;
      `aj bootstrap` as that worker repairs it.
- [x] V15: a jailer session in this checkout runs `nix flake check`,
      `git add`, `sudo -v`; is refused `git commit`, `git push`,
      `cat ~/.ssh/id_ed25519`. (Today's session did `git add` and
      `sudo -n` fine; the refusals were not tried on purpose.)
- [x] V12 passes, 2026-10-29 afternoon (roadmap item 13 has the hook
      line). V10 and V11 were cut by item 14 on 2026-10-28.
- [x] V4: owner watching a worker, `sudo -u w-acme -i tmux attach`.
      Passes 2026-10-29 evening (section 0).
- [x] Whether `permissions.deny Read(...)` stops the Read tool for the
      unsandboxed jailer (roadmap, item 14).
- [ ] The three managed-only keys in the law, each decided on its own.

## 5. Release itself (decide first thing)

- [x] Rename `customer` → `org` everywhere (decided 2026-10-28 evening:
      no consulting speak; `project` is out because it already names the
      pair, `AI_JAIL_PROJECT=acme/infra`). 98 occurrences in 17 files:
      roadmap 18, ajmux.nix 11, bootstrap.sh 11, README 9, sessions 8,
      runbook 7, tests. Placeholders `<customer>/<repo>` → `<org>/<repo>`,
      `w-<customer>` → `w-<org>`, `<c>` stays. Worker user names, the
      receipt's `root.workers` and the env var don't change. Define
      "org" once in the README: whoever the work is for (a client, a
      team, an open-source org, yourself); one Linux user per org is
      the boundary. Then reread README and runbook for sentences that
      lean on the client framing. Before the release, not after.
- [x] Say what "release" means: a tag on `main` plus README "current
      state" true, or also the nixos-wsl side installable from scratch
      by `install-wsl.ps1` (untested end to end since the rename).
- [x] README current-state pass: the host table, the lockdown table
      (`a worker cannot read another user's home (0750; untested live)`
      is now tested live), the three ai-jailer pieces nixos-wsl consumes.
- [x] Changelog entry for the release day; the roadmap's Done section.
- [ ] Not for the release, parked: the factory-shell staleness signal
      (`docs/suggestion.md` 3); moving anything into home-manager (no:
      decided 2026-10-28); automating the lock bump (no: `verify.sh`
      says when it matters).

## 6. Token and context cost in cells and the factory (checked 2026-10-29, late)

Six ideas from the evening of 2026-10-29, each checked against the code
before it was written here. Order is by value over cost. None of them
gates the release; 6.1 to 6.5 are an hour together, do them after
section 5 or when touching the file anyway.

- [x] 6.1 CLAUDE.md "Checks" (factory): drop the tar copy and `-L` as
      the default. Verified live tonight: this jailer session (law only,
      no sandbox) built `nix build .#checks.x86_64-linux.managed-tree-test
      --no-link` straight on the checkout, 4 s, three lines of output.
      Write: an unsandboxed session runs `nix flake check` and
      `nix build .#checks...` on the checkout; `-L` or `nix log` only
      after a failure; keep the `git ls-files | tar` copy as the fallback
      for a sandboxed worker session. One full `nix flake check` on the
      checkout still to be run once before the fallback paragraph shrinks.
      Ran 2026-10-29 evening from an unsandboxed session: all checks
      passed, about two minutes.
- [x] 6.2 `hooks/env-guard.sh`: refusals that say what to do instead.
      Models answer a bare `blocked` by trying flag variants for 2-3
      turns. Keep the prefix text (`pkgs/aj/check.sh` 185 matches only
      `env-guard:`; `tests/hook-test.sh` 36 discards stderr), append one
      clause. Rule 1, all three `git history/index write blocked` sites:
      `: stage with git add, branch with git switch -c; revert a file
      with git show HEAD:<path> > <path>`. Rule 2: `terraform write
      blocked: plan/validate only; propose apply/state commands to the
      human`, `az write blocked: read/list/show only; propose write
      commands to the human`. L1 is fine as is (the model stops).
- [x] 6.3 `pkgs/aj/init.sh` 217-234, the cell CLAUDE.md contract:
      rewrite for action, not plumbing. The first paragraph explains
      where the three layers come from, which a worker never needs;
      missing are the rules that save discovery turns. Keep the heading
      `## Environment contract (ai-jailer)` (line 236 detects it with
      `grep -F 'ai-jailer'`); update `tests/aj-init-test.sh` 163-164,
      which assert two phrases of the old text. New bullets:
      tools and non-secret identifiers (`ARM_TENANT_ID`, ...) come from
      `devenv.nix`, read it first instead of `which`/`--version` probes
      or looking for the dotenv file; never read the dotenv files,
      tfvars, tfstate, `.devenv/`, `.direnv/`; never edit `devenv.nix`,
      `devenv.yaml`, `devenv.lock`, `.envrc`, `.claude/`, a change goes
      as a unified diff to `proposals/<YYYY-MM-DD>-<topic>.patch` or into
      the reply; stage with `git add` only, commit/push/restore/
      checkout --/reset are blocked, revert with `git show HEAD:<f> > <f>`;
      cloud and IaC read/plan only, `az` scoped with `--query` or
      `-o table`/`-o tsv`, never unfiltered JSON; a refusal (`env-guard:`,
      a deny rule, a sandbox error) is expected: stop and propose, no
      workarounds. Keep "credential paths are hidden; clone over HTTPS".
- [x] 6.4 `pkgs/aj/init.sh` 212: add `proposals/` to the .gitignore
      lines (the factory's own .gitignore has it, the cell template does
      not, yet CLAUDE.md promises the path is gitignored) and
      `ensure_lines .ignore 'devenv.lock'` so ripgrep-backed Grep skips
      the tracked lockfile (gitignore does not cover tracked files).
      Test: a "plans .ignore" dry-run check next to `tests/aj-init-test.sh`
      line 44.
- [x] 6.5 (done, then reverted the same day: a `Read(...)` deny glob feeds
      the sandbox's denyRead and masked the store through `.devenv/`'s
      symlinks; changelog 2026-10-29) `lib/deny-rules.nix`: add `"Read(**/.devenv/**)"` and
      `"Read(**/.direnv/**)"` to the credentials/`jail` side, not the
      law (`tests/managed-tree-test.sh` 34 asserts the law's shape; it
      would still pass, but the rule is the workers'). Not in
      `sandbox.filesystem.denyRead` (`lib/settings.nix`): Bash must still
      run binaries under `.devenv/profile/bin`. A Read deny also blocks
      Edit/Write (deny-rules.nix ~100), intended. No test asserts the
      sibling `.terraform/**` rule today; add one for all three or none.
- [ ] 6.6 Measure first, then maybe: quiet Terraform and az in cells via
      `env` in `devenv/devenv.nix` (`lib.mkIf cfg.enable`, `lib.mkDefault`
      per key: `TF_CLI_ARGS_plan = "-no-color -compact-warnings"`,
      `TF_CLI_ARGS_{validate,init,show} = "-no-color"`,
      `AZURE_CORE_ONLY_SHOW_ERRORS = "true"`, `AZURE_CORE_NO_COLOR =
      "true"`; never a global `TF_CLI_ARGS`, `-compact-warnings` breaks
      init/workspace; Terraform ignores NO_COLOR). The plumbing is right:
      the hook's `$CLAUDE_ENV_FILE` preamble runs `direnv export` before
      every Bash call. But the Bash tool has no TTY (checked tonight:
      `[ -t 1 ]` false), and both tools drop colour without one, so the
      ANSI half of the claim is moot; what is left is `-compact-warnings`
      and the az preview/survey banners. Do it only after the first
      `terraform plan` or `az` run in a cell shows the noise in a
      transcript (`aj check` writes them under its `transcripts:` dir).
- [ ] 6.7 Parked: splitting `pkgs/aj/bootstrap.sh` (1,335 lines) into
      common/bootstrap/doctor/reset. It helps only factory sessions that
      edit doctor or reset, and the cut is not clean: `report()` (line
      1068) is called by both `doctor` and `bootstrap|upgrade` (line
      1320), so doctor's part would be in bootstrap's build too, or
      `report` moves to common. Constraints if ever done: `usage()`
      (169) reads its own file's header up to the first `# shellcheck`
      line, so the per-command header must come first in the merged
      text; `CMD` from `AI_JAILER_CMD` (`pkgs/aj.nix` 122) and the
      dispatch stay; `tests/aj-bootstrap-test.sh` and
      `tests/aj-doctor-test.sh` pass unchanged. Revisit after the
      release, only if the file keeps growing.

## Routines that stand after today

- Rules changed (hook, law, jail, `aj`): `aj upgrade --no-profile
  --workers acme,globex` from the checkout shell. No push needed.
- `ajmux`, `direnv.toml` or `tmux.conf` changed: push, then in
  `/etc/nixos`: `nix flake update ai-jailer && nh os switch`.
  `verify.sh` fails when this was forgotten and it matters.
- After any rebuild: `sh /etc/nixos/scripts/wsl/verify.sh`.
- `aj` outside the checkout: `nix run ~/code/ai-jailer#aj -- <cmd>`.
