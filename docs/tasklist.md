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

## 1. Close today's loop (15 min)

- [ ] ai-jailer: commit the staged hook-test fix.
- [ ] In the checkout shell: `direnv reload`, then
      `aj upgrade --no-profile --workers acme,globex`.
- [ ] `sudo -u w-acme -i aj init acme/infra --yes`: idempotent; must end
      with the `ajmux -n` note and "Ready", hook-test 443/443.
- [ ] Run the DAC and linger lines that were never pasted:
      `sudo -u w-acme -i sh -c 'ls /home/nixos'` (denied),
      `sudo -u w-acme -i sh -c 'ls /home/w-globex'` (denied),
      `sudo -u w-acme -i sh -c 'test -d /run/user/$(id -u) && echo linger ok'`.

## 2. Two validated bootstrap fixes (1 h, with tests)

Both checked against the code on 2026-10-28; see the chat's verdict.

- [ ] Bare `aj upgrade` loads `.root.workers[]` from the receipt into
      `WORKERS` when none were passed and `--no-root` is off
      (`pkgs/aj/bootstrap.sh`, the `upgrade` branch of the dispatch).
      README line 234 already promises this. Test: bare `upgrade` after
      a `--workers` bootstrap runs `upgrade` as each worker. Decide: a
      receipt worker the host lacks gets `useradd` again on every
      upgrade (what doctor tells the operator to do anyway).
- [ ] `useradd -s "$(command -v bash)"` instead of `/bin/bash`, and
      `true` instead of `/bin/true` in doctor's bwrap probe. Real on plain
      NixOS (only `/bin/sh` there); moot on NixOS-WSL, which links
      `/bin/bash` and `/bin/true` itself. Test 20's exact `useradd` line
      in `tests/aj-bootstrap-test.sh` changes with it.

## 3. Small wording fixes seen today (20 min)

- [ ] The per-worker `warn the ai-jailer ref is this aj's store path …
      a later upgrade cannot move it` is misleading: an owner-side
      `aj upgrade --workers` prefetches a fresh snapshot and does move
      it. Only a worker upgrading on its own cannot.
- [ ] The "Next: open a new terminal (PATH and NIX_SSL_CERT_FILE come
      from profile.d and ~/.bashrc.d)" trailer is stale on NixOS, where
      bootstrap writes neither.
- [ ] `verify.sh` in nixos-wsl: nothing pending; the README there could
      name the new lock-drift check in its verify table.

## 4. Live verification still open in the roadmap (the release gate)

Item 14's gate, from `docs/roadmap.md` "The first live run": V12 to
V15, plus V1 to V9 of item 11 and V10, V11 of item 13 as narrowed. Run
them in `acme/infra` as `w-acme`, paste results into the roadmap's
boxes, tick what passes.

- [ ] V13: a worker session starts, `aj check` passes as `w-acme`
      (API calls; the first live `aj check` transcript is V8).
- [ ] V14: edit `~/.claude/settings.json` as the worker (drop a deny
      rule): every tool refused with the hook's `differs from` message;
      `aj bootstrap` as that worker repairs it.
- [ ] V15: a jailer session in this checkout runs `nix flake check`,
      `git add`, `sudo -v`; is refused `git commit`, `git push`,
      `cat ~/.ssh/id_ed25519`. (Today's session did `git add` and
      `sudo -n` fine; the refusals were not tried on purpose.)
- [ ] V12, V10, V11: the managed sandbox list and `failIfUnavailable`
      cases, as written in the roadmap.
- [ ] V4: owner watching a worker, `sudo -u w-acme -i tmux attach`.
- [ ] Whether `permissions.deny Read(...)` stops the Read tool for the
      unsandboxed jailer (roadmap, item 14).
- [ ] The three managed-only keys in the law, each decided on its own.

## 5. Release itself (decide first thing)

- [ ] Say what "release" means: a tag on `main` plus README "current
      state" true, or also the nixos-wsl side installable from scratch
      by `install-wsl.ps1` (untested end to end since the rename).
- [ ] README current-state pass: the host table, the lockdown table
      (`a worker cannot read another user's home (0750; untested live)`
      is now tested live), the three ai-jailer pieces nixos-wsl consumes.
- [ ] Changelog entry for the release day; the roadmap's Done section.
- [ ] Not for the release, parked: the factory-shell staleness signal
      (`docs/suggestion.md` 3); moving anything into home-manager (no:
      decided 2026-10-28); automating the lock bump (no: `verify.sh`
      says when it matters).

## Routines that stand after today

- Rules changed (hook, law, jail, `aj`): `aj upgrade --no-profile
  --workers acme,globex` from the checkout shell. No push needed.
- `ajmux`, `direnv.toml` or `tmux.conf` changed: push, then in
  `/etc/nixos`: `nix flake update ai-jailer && nh os switch`.
  `verify.sh` fails when this was forgotten and it matters.
- After any rebuild: `sh /etc/nixos/scripts/wsl/verify.sh`.
- `aj` outside the checkout: `nix run ~/code/ai-jailer#aj -- <cmd>`.
