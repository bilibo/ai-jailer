# ai-jailer

Guard rails for Claude Code on a Linux host with Nix. Each client or team
(an "org") gets its own Linux user; its agents run as that user, in a
bubblewrap sandbox, under a deny list and a fail-closed hook, with no push
credential and no sudo. You drive them from your own account with
`ajmux <org>/<repo>`, read their staged diffs through the group, and do the
commits and pushes yourself. Built from Claude Code's own mechanisms
(managed settings, permission rules, hooks, the Bash sandbox) plus plain
Unix users; nothing is patched.

The spirit: the AI is the escape risk, not the human. So the rules live
where an agent cannot edit them, in root-owned `/etc/claude-code` and in the
worker user's own settings file, which the hook compares against the
root-owned reference before every tool call. A repo adds allow rules and
network hosts for its own work; it never loosens anything. Whatever fails,
fails closed: a hook error refuses the call, a missing sandbox refuses the
session.

Don't mistake it for a hard security boundary either. The hook matches
command text, a worker's own home is readable to it, and every unix socket
on the host is reachable from inside the sandbox (Claude Code's sandbox on
Linux is all or nothing there). "What to expect" below says what holds and
what does not. Status: `v0.1.0` (2026-10-29) ran end to end on NixOS-WSL
with two workers. On Fedora and Ubuntu the one-user shape before it ran
live; the worker shape is covered by the stubbed-host tests only.

## Where things are

- `lib/`: pure Nix. `deny-rules.nix` holds the law (what binds everyone on
  the host) and the jail (what binds a worker); `settings.nix` renders the
  three settings bodies, law, jail and repo; `managed-tree.nix` is what
  gets linked at `/etc/claude-code`.
- `hooks/env-guard.sh`: the guard hook, kept small on purpose because it is
  the one script that must be right. `tmux-notify.sh` turns a tmux window
  orange when its session waits for you.
- `devenv/devenv.nix`: the module every governed repo imports. It writes
  the repo's `.claude/settings.json` at every shell entry, read-only, from
  the `ai-jail.*` options.
- `pkgs/`: the `aj` CLI (`aj/bootstrap.sh`, `init.sh`, `check.sh`), the
  `ajmux` launcher, `tmux.conf` and `direnv.toml`, and a `claude-code`
  override that drops the `LD_LIBRARY_PATH` line of nixpkgs' wrapper.
- `scripts/install.sh`: the one install route for a host without Nix.
- `tests/`: one suite per piece; `nix flake check` runs them all without
  Claude Code.
- `docs/runbook.md`: the operator's reference (host configuration,
  verifying, troubleshooting, known gaps). `docs/project-devenv.md`: a
  project's `devenv.nix` for someone who has not used Nix; `aj init` links
  it from the file it writes.

On a host after bootstrap, `/etc/claude-code/` holds `managed-settings.json`
(the law), `jail-settings.json` (the reference copy of a worker's rules)
and `hooks/`. Each worker is `w-<org>` with a 0750 home, its clones under
`~/code/git/<org>/<repo>` and its own Claude login in `~/.claude`.

## Install

Any Linux with git and sudo. The script installs Nix where it is missing
(Fedora 44 and newer: the distro's packages; elsewhere the nix-installer;
NixOS: nothing), then runs `aj bootstrap`:

```sh
git clone https://github.com/bilibo/ai-jailer.git ~/code/ai-jailer
cd ~/code/ai-jailer
scripts/install.sh --workers acme,globex      # --check prints the plan and changes nothing
aj doctor
```

Bootstrap links the managed tree at `/etc/claude-code`, creates a user and
group per worker plus the `agents` marker group, puts you in each worker's
group, turns linger on, installs the sudo rule (`<you> ALL=(%agents)
NOPASSWD: ALL`; `--owner-sudo password|none` changes it), then sets each
worker up as that user: direnv, devenv, `ajmux` and `aj` in its profile,
tmux, the code root, a git identity. Running it again installs nothing
twice.

With Nix already on the host (NixOS, NixOS-WSL) skip the script: `devenv
shell` in the checkout (or `nix run nixpkgs#devenv -- shell`), then `aj
bootstrap --workers acme,globex`. On NixOS what the system configuration
owns is printed instead of written: the `nix.settings` block for flakes and
the devenv cache, and the `boot.kernel.sysctl` line where user namespaces
are confined. No sudo rule is installed there (your own sudo serves), and
the workers come from `useradd`, which holds while `users.mutableUsers` is
true, the default. The `/etc/claude-code` link survives rebuilds; nothing of
the jailer goes into the host configuration.

Windows: install NixOS-WSL first.
[bilibo/nixos-wsl](https://github.com/bilibo/nixos-wsl) is the reference
host and already carries `ajmux` and the tmux rules; then the same two
commands inside the distro. Bootstrap detects WSL and links a tree that
also hides `/mnt/c` and `/run/WSL` from the sandbox.

Later: `git pull && aj upgrade` moves the rules, the profile packages and
the workers to the checkout's lock. `aj reset` undoes what bootstrap did,
keeps the worker users and prints the `userdel -r` lines for you to run.

## Daily use

A repo under the jailer is a cell: it imports `ai-jailer/devenv` and gets
its tools from a devenv shell that wraps every command the agent runs.
Onboarding is done as the worker, because the repo lives in that user's
home:

```sh
sudo -u w-acme -i claude auth login      # once per worker, with the account for that org's work
sudo -u w-acme -i aj init acme/infra     # a new directory under the worker's code root, or a path to an HTTPS clone
```

`aj init` writes `devenv.yaml`, `devenv.nix` (every `ai-jail` option
listed, the unused ones commented out), `.envrc`, `.gitignore`,
`.worktreeinclude` and a CLAUDE.md contract, shows what the first shell
entry will trust and waits for a `y`, then enters the shell and runs the
settings and hook tests on the result.

Then, from your own terminal:

```sh
ajmux acme/infra                     # a tmux session per project, a window per call; hands over with sudo -u w-acme -i
ajmux acme/infra --worktree          # a session that will edit files, in .claude/worktrees/<name>
ajmux acme/infra -p "explain the module layout"
sudo -u w-acme -i                    # a shell as the worker: git, aj, a look around
```

Each terminal gets its own view of the project's windows, so one VS Code
tab per Claude session works. A window turns orange when its session waits
for you (end of turn, a permission prompt, a minute idle) and clears on
your next prompt.

Agents stage, diff and branch; the commit is yours. Read a worker's staged
work through the group with `git -C ~w-acme/code/git/acme/infra diff
--cached`. The worker has nothing to push with; how its commit best reaches
the remote (commit as the worker and fetch into your clone, or push from
theirs with your credential) is still an open question.

When an agent needs a tool, a rule or a network host it cannot edit
`devenv.nix`: it writes the change to `proposals/<date>-<topic>.patch` in
the repo (gitignored) or into its reply, and stops. You read it, `git
apply` it as the worker, `direnv allow`, done. `docs/project-devenv.md`
has every kind of change with the lines to paste.

## What to expect

A worker's session, in a cell or anywhere else as that user:

- **Refused by the deny list and the hook**: reading credentials (`.env`,
  `*.tfvars`, `*.tfstate`, the Claude login, `~/.ssh`, the GitHub tokens
  on disk, `~/.azure`); `git commit`, `git push` and every history rewrite;
  cloud writes (`terraform apply`, `az ... create|delete|update`, `pulumi
  up`); system changes (`sudo`, `nix profile`, `nixos-rebuild`,
  `systemctl`); edits to the project's configuration (`devenv.nix`,
  `.envrc`, `.claude/`) and to the user's own (`~/.bashrc`, `~/.claude/**`,
  `~/.config/**`); plugins and mods; `direnv allow`; tmux commands other
  than the read-only ones; a nested `claude` with flags that would skip
  settings; bypass mode.
- **Sandboxed**: every Bash command runs in bubblewrap with no unsandboxed
  fallback. `~/.ssh` and the token files are hidden; `SSH_AUTH_SOCK`,
  `ARM_CLIENT_SECRET` and the GitHub tokens are stripped from every
  command. Network is an allowlist (Azure, Terraform, GitHub and the trivy
  registries, plus what the cell adds); any other host prompts in an
  interactive session and is refused in a `-p` one.
- **Linux**: a 0750 home no other user can list, no sudo, no push
  credential, not a trusted Nix user. A worker cannot start a session in
  another org's repo.
- **Checked before every tool call**: that the worker's
  `~/.claude/settings.json` still carries the jail and that the sandbox
  resolves on, whatever a repo or local file says. A worker whose file
  drifted gets every tool refused until `aj bootstrap --no-root --yes` as
  that worker rewrites it.

Your own sessions, this checkout's included, get the law and nothing else:
credential reads, `git commit` and `git push` refused, bypass mode off; no
sandbox and no other rule.

A blocked call looks like one of three things, and all three are the
point: an `env-guard: ... blocked` line (the hook; final), a permission
denial naming a rule such as `Bash(git push *)` (the deny list; final), or
a sandbox error (`Operation not permitted`, a refused host). The contract
in the cell's CLAUDE.md tells the agent to propose or ask, never to work
around. If a legitimate command keeps hitting a block, the fix is an allow
rule in that repo's `devenv.nix`, not a looser host rule.

What does not hold, by design or not yet: the hook reads text, so a
command computed at runtime (`$(echo git) push`, `base64 -d | sh`) gets
past it, and the sandbox and the missing credentials are the layer for
that; every unix socket is reachable, including the worker's own tmux
server, which runs unsandboxed (the hook refuses tmux by text only); reads
inside the worker's home are open except the credential paths; `/add-dir`.
The runbook's "Known gaps" has the full list with the measurements behind
it.

## Make it yours

Host-wide policy is `host.nix` at the checkout root, gitignored, applied
by `aj upgrade`:

```nix
{
  extraDeny = [ "Bash(az devops *)" ];
  extraAllowedDomains = [ "dev.azure.com" ];
  allowLocalCommits = false;   # true lets agents commit (never push)
  allowMemoryEdits = false;    # Claude's auto-memory is a persistence channel across sessions
  allowConnectors = false;     # claude.ai connectors are MCP servers outside the sandbox
}
```

A cell's `devenv.nix` adds its own: `ai-jail.settings.permissions.allow`
for the commands the project runs all the time,
`ai-jail.extraAllowedDomains` for its hosts, `ai-jail.extraDeny` for more
refusals, and `ai-jail.enable = false` to turn the project layer off (the
host rules still apply). Project identifiers (tenant, subscription,
region) go into `devenv.nix` as `env.X = "..."`, committed, so the agent
and the tools see them; secrets stay in `.env`, which only your own shell
loads.

Tests: `nix flake check` runs every suite without Claude Code. `sudo -u
w-acme -i aj check ~/code/git/acme/infra` runs the live checks as the
worker: around twenty `claude -p` sessions judged on their transcripts and
on the files afterwards. It costs API calls; run it after a Claude Code
upgrade.

## Quirks worth knowing

- Agents never see `.env`: the sandbox mounts it as `/dev/null` and the
  hook refuses commands that name it. A project that keeps its tenant and
  subscription IDs there sees `az` and `terraform plan` fail inside the
  sandbox until those lines move to `devenv.nix`.
- The hook strips quotes before matching, so a prompt that merely mentions
  a secret path or a launch flag is refused too (`claude -p "why is .env
  hidden"`). Rephrase.
- `direnv allow` is yours, run as the worker; sessions are refused it by
  text. A new repo needs it twice (the first load writes `devenv.lock`). A
  `devenv.local.nix` or `devenv.local.yaml` stops the shell from loading
  at all, because devenv would import it with no approval.
- Claude Code rewrites the worker's `~/.claude/settings.json` for `/model`
  and the mode switch. The hook compares keys, not the file, and leaves
  `permissions.defaultMode` out; anything else that differs locks the
  worker out until `aj bootstrap --no-root --yes` as that worker.
- "Yes, and don't ask again" writes `.claude/settings.local.json`, which
  the hook refuses in a session. The file is still written and applies from
  the next session; project allow rules belong in `devenv.nix`.
- Project allow rules wait for the folder trust dialog in an interactive
  session; `-p` treats the folder as trusted.
- The claude.ai account's connectors (Gmail, Drive, Linear, ...) are off
  for workers and in cells by default; `ai-jail.allowConnectors = true` in
  a repo or `allowConnectors` in `host.nix` turns them on. Skills and
  plugins synced from the account are off for workers too.
- A `Read(...)` deny rule becomes a sandbox `denyRead` and expands through
  symlinks, which is why there is no rule on `.devenv/` or `.terraform/`:
  one on `.devenv/` put a tmpfs over `/bin/bash` and killed every command.
- Claude Code from Nix comes through `pkgs/claude-code.nix`: nixpkgs'
  wrapper exports an `LD_LIBRARY_PATH` that every command and hook inherits
  and that kills distro binaries. The override drops it, and audio output
  goes with it.
- The settings keys were last checked against Claude Code 2.1.30x. A key
  that stops existing is silently ignored, which is the dangerous
  direction: re-read the settings reference and run `aj check` after an
  upgrade.
- Your own account is where an SSH key lives, so it is the one place one
  can be misused: use a FIDO2 key, or a passphrase key with `IdentityAgent
  none` for the git host, and never `ssh-keygen -N` (it puts the
  passphrase in shell history).
- Inside a sandboxed session `nix flake check` on the checkout fails (the
  sandbox masks the untracked dotfiles); `CLAUDE.md` has the
  copy-the-tracked-files recipe. The jailer's own sessions are unsandboxed
  and run it directly.
