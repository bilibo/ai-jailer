# ai-jailer

Guard rails and per-project dev environments for Claude Code on Linux, built
from Claude Code's own managed settings, hooks and sandbox, ordinary Unix
users, and Nix (`devenv` + `direnv`).

Out of the box a coding agent runs as you. It has your SSH keys, your cloud
tokens, your git credentials and your sudo, and sooner or later it will try
to use them because you asked for something ambiguous or because a file it
read told it to. Putting a deny list in `~/.claude/settings.json` does not
help when the agent runs as the user who owns that file. ai-jailer gives
every client or project group its own Linux user (`w-acme`, `w-globex`).
The agent runs as that user: sandboxed with bubblewrap, with no credentials,
no sudo and nothing to push with. The rules live in root-owned
`/etc/claude-code` and in the worker's own settings file, which a hook
checks against the root-owned reference copy before every tool call. You
drive it from your own account, inspect what it staged through the worker's
group, and commit and push yourself.

Nix and `devenv` handle the rest of the day-to-day workflow. Instead of
installing compilers, cloud CLIs and language runtimes globally on the host,
each repo's `devenv.nix` declares both its devshell tools and its `ai-jail.*`
rules. `direnv` loads them when you enter the directory, and the hook loads
the same shell into every command the agent runs.

Don't mistake this for a hard security boundary. The hook matches command
text, the worker can read its own home directory, and Claude Code's sandbox
on Linux leaves every Unix socket open, including the worker's own tmux
server, because Terraform's providers and the Nix daemon need them and the
filter is all or nothing. What it buys you is that an accident or a prompt
injection ends in a refused tool call instead of a push to `main` or a
`terraform apply`. Code you do not trust still belongs in a VM. I run this on
[bilibo/nixos-wsl](https://github.com/bilibo/nixos-wsl) with two workers,
which is where `v0.1.0` (2026-10-29) was tested end to end. Fedora and
Ubuntu ran live before the multi-user split; the multi-user setup there is
covered by stubbed-host tests only so far.

## Where things are

- `lib/deny-rules.nix`, `lib/settings.nix` and `hooks/env-guard.sh`: the
  rules. The Nix files define what everyone is refused, what a worker is
  refused on top, and what the bubblewrap sandbox hides; `env-guard.sh` is
  the PreToolUse hook that runs outside the sandbox before every tool call
  and actually says no. Read these for the spirit of the project.
- `devenv/devenv.nix`: what a governed repo imports. It writes a read-only
  `.claude/settings.json` from the `ai-jail.*` options on every shell entry.
- `pkgs/`: `aj` (`bootstrap`, `doctor`, `init`, `check`, `upgrade`, `reset`),
  `ajmux` (the tmux launcher that hands over to the worker), and the tmux
  and direnv configs. `scripts/install.sh` puts Nix on a host that lacks it,
  then runs `aj bootstrap`.
- `docs/runbook.md`: operator notes, verification steps, troubleshooting and
  known gaps. `docs/project-devenv.md`: a practical guide to customizing a
  repo's `devenv.nix` (packages, languages, env vars, allow rules) without
  needing to know Nix first.

## Install

The install is `aj bootstrap`, run from this checkout's devenv shell. Any
Linux with Nix, git and sudo:

```sh
git clone https://github.com/bilibo/ai-jailer.git ~/code/ai-jailer
cd ~/code/ai-jailer
devenv shell                                # nix run nixpkgs#devenv -- shell if devenv is not on PATH yet
aj bootstrap --workers acme,globex          # --dry-run shows the plan and changes nothing
aj doctor
```

Bootstrap links `/etc/claude-code`, creates a user and group per worker with
a `0750` home, puts you in those groups, enables systemd linger, writes one
sudoers rule (you to the workers, never the other way), and sets each worker
up with direnv, devenv, tmux and a git identity. Running it a second time is
a no-op.

On a host without Nix (Fedora, Ubuntu, anything that is not NixOS), run
`scripts/install.sh --workers acme,globex` instead: it installs Nix
(Fedora's own packages on Fedora 44+, `nix-installer` elsewhere), then runs
the same `aj bootstrap` with your flags and `aj init` on the checkout so its
shell exists. `--check` prints the plan and changes nothing. Afterwards a
new terminal has `aj` on PATH through `profile.d`; so does this checkout's
shell (`direnv allow` here, or `devenv shell`), which `aj init` already
built.

On NixOS (including NixOS-WSL) anything owned by the system configuration is
printed instead of written (the `nix.settings` block and the user-namespace
sysctl), no sudo rule is installed because your own sudo already covers it,
and workers are created with `useradd` (leave `users.mutableUsers` at its
default). Nothing from ai-jailer goes into your NixOS configuration.

If you are on Windows or want a reference NixOS setup to start from, look at
[bilibo/nixos-wsl](https://github.com/bilibo/nixos-wsl): it sets up a
single-file NixOS-WSL flake with `home-manager`, `nix-ld`, Windows interop
turned off, and `ajmux`, `direnv.toml` and the tmux rules preinstalled.
Bootstrap detects WSL automatically and hides `/mnt/c` and `/run/WSL` from
the sandbox.

`git pull && aj upgrade` moves the host and workers to the new revision.
`aj reset` reverses what bootstrap recorded: the `/etc/claude-code` link, the
sudoers rule, linger and the jail keys in each worker's settings. It leaves
the worker users and their homes alone and prints the `userdel -r` commands
if you want them gone too.

## Using it

Each worker logs in once with its own Claude account, then you initialize
repos under it:

```sh
sudo -u w-acme -i claude auth login
sudo -u w-acme -i aj init acme/infra    # new dir under the worker's code root, or path to an HTTPS clone
```

`aj init` writes `devenv.yaml`, `devenv.nix`, `.envrc`, `.worktreeinclude`,
a `CLAUDE.md` contract and the gitignore lines, shows you what the first
shell entry will trust before running it, and runs the settings and hook
tests against the result. Then, from your own terminal:

```sh
ajmux acme/infra                        # a tmux session per project, a window per call, as w-acme
ajmux acme/infra --worktree             # isolated git worktree when the session will edit files
ajmux acme/infra -p "explain the module layout"
sudo -u w-acme -i                       # a shell as the worker when you want to poke around
```

Each terminal gets its own grouped tmux view of the project's windows, so
multiple VS Code tabs attached to the same project do not follow each other
around. The window tab turns orange when the agent stops or waits on a
prompt.

Agents stage, diff and branch; `git -C ~w-acme/code/git/acme/infra diff --cached`
from your own account shows you what changed, and the commit and push are
yours. Workers have no SSH keys or tokens, so they cannot push; right now
you either commit as the worker and fetch the branch from its clone into
your own to push, or push from its clone using your credentials. Neither is
tested yet. Since your account is the only one on the box with a push key,
put it on a hardware key (FIDO2) or a passphrase with `IdentityAgent none`
so nothing caches it in memory.

When the agent needs a package, an allow rule or a network host, it cannot
edit `devenv.nix`. It writes a patch to `proposals/` in the repo and stops.
You read it, `git apply` it as the worker, and run `direnv allow`. If an
agent keeps hitting a block on a legitimate command, add an allow rule in
that repo's `devenv.nix` rather than loosening the host.

Your own Claude sessions on the host (including in this repo) get the base
host rules and nothing else: no credential reads, no `git commit`, no
`git push`, no bypass mode, and no sandbox. The jail is for the workers.

## Make it yours

Each project's coding environment and agent rules live together in that
repo's `devenv.nix`. `direnv` loads the shell on `cd` and the hook wraps
every Bash command Claude Code runs in it, so you never have to
`source .venv/bin/activate` or install project tools globally:

```nix
{ pkgs, ... }: {
  packages = [ pkgs.azure-cli pkgs.terraform pkgs.tflint ];

  languages.python = {
    enable = true;
    uv.enable = true;
    venv.enable = true;
  };

  env.ARM_TENANT_ID = "00000000-0000-0000-0000-000000000000";

  ai-jail.settings.permissions.allow = [
    "Bash(terraform plan *)"
    "Bash(uv run pytest *)"
  ];
  ai-jail.extraAllowedDomains = [
    "dev.azure.com"
    "pypi.org"
    "files.pythonhosted.org"
  ];
}
```

How Nix and language tools split the work here:

- **System CLIs and compilers (`packages`, `languages.*`)** are fetched by
  Nix outside the sandbox when the shell is evaluated after `direnv allow`.
  Search package names at `search.nixos.org` or with `devenv search <name>`.
  Unfree packages (like `terraform`) require `allow_unfree: true` in
  `devenv.yaml`.
- **Virtualenvs and language package managers (`uv`, `pip`, `cargo`, `npm`)**
  run inside the repo shell as usual, with the virtualenv already on `PATH`.
  Because package managers download dependencies inside the bubblewrap
  sandbox at runtime, add their registries (`pypi.org` and
  `files.pythonhosted.org` for `uv`/`pip`, `index.crates.io` and
  `static.crates.io` for `cargo`, `registry.npmjs.org` for `npm`) to
  `ai-jail.extraAllowedDomains` if you want the agent to sync or build
  packages itself.
- **Variables vs. secrets**: Non-secret identifiers (tenant and subscription
  IDs, regions) go in `env.X = "..."` in `devenv.nix` so tools can read them
  inside the sandbox. Secrets stay in `.env`, which only a human shell loads.

An ordinary app project works the same way, with the shell standing in for
`.env`:

```nix
{ pkgs, ... }: {
  languages.javascript = { enable = true; npm.enable = true; };
  services.postgres = { enable = true; initialDatabases = [ { name = "app_dev"; } ]; };
  env.PORT = "3000";
  env.APP_ENV = "development";
  dotenv.enable = true;                              # .env holds the secrets; only your shell loads it
  ai-jail.extraAllowedDomains = [ "registry.npmjs.org" ];
}
```

The agent runs `npm test` with the same `PORT` and `APP_ENV` you have,
against the Postgres that `devenv up` starts, and sees an empty `.env`; the
Stripe test key in there is yours. Tests that need a real third-party
credential run against a mock or are your run. That is the point, not a
side effect: an agent that needs your API keys to pass the test suite is
the channel this tool closes. Per-developer values that are not secrets go
in a gitignored file with another name, loaded by
`dotenv.filename = [ ".env" "local.vars" ]`; a name ending in `.env` is
caught by the hook like `.env` itself. Whether a sandboxed dev server may
bind a port is untested so far (Claude Code's `allowLocalBinding`, which
nothing here sets).

`docs/project-devenv.md` has more copy-paste examples for someone new to Nix.

Host-wide policy lives in `host.nix` next to `flake.nix` (gitignored) and is
applied by `aj upgrade`:

```nix
{
  extraDeny = [ "Bash(az devops *)" ];
  extraAllowedDomains = [ "dev.azure.com" ];
  allowLocalCommits = false;   # true lets agents commit locally; push stays yours
  allowMemoryEdits = false;    # auto-memory persists across sessions
  allowConnectors = false;     # claude.ai connectors run as MCP servers outside the sandbox
}
```

`nix flake check` runs the test suites without Claude Code.
`sudo -u w-acme -i aj check ~/code/git/acme/infra` runs the live suite as
the worker: around twenty `claude -p` sessions judged on what they actually
did on disk and in the transcript. It costs API calls; run it after upgrading
Claude Code.

## Quirks worth knowing

- The agent never sees `.env`. The sandbox mounts it as `/dev/null` and the
  hook refuses any command that names it. Projects that keep tenant or
  subscription IDs in `.env` will see `az` and `terraform plan` fail until
  those non-secret variables move to `devenv.nix`. The rule is `.env.*`
  too, so `.env.example` and `.env.local` are hidden as well; name a
  template `env.example` if the agent should read it. There is no switch
  for this: it is a host-wide rule, and `.env` is where secrets live by
  convention, so move the variables rather than the rule.
- Never put a `Read(...)` deny rule on `.devenv/` or `.terraform/`. Claude
  Code turns Read denies into bubblewrap `denyRead` mounts and follows the
  symlinks inside the denied directory, so denying `.devenv/` mounted a
  tmpfs over the store paths it points at, the bash package included, and
  every sandboxed command died with `bwrap: execvp /bin/bash: No such file`.
- The hook strips quotes before matching command text, so a prompt that
  mentions a secret path or launch flag gets refused too (`claude -p "why is
  .env hidden"`). Rephrase it.
- `direnv allow` must be run by you as the worker; the agent is refused it.
  A newly initialized repo needs it twice because the first evaluation writes
  `devenv.lock`. Any `devenv.local.nix` or `devenv.local.yaml` stops the
  shell from loading at all, since devenv would import it without
  `direnv allow`.
- Choosing "Yes, and don't ask again" in Claude Code writes
  `.claude/settings.local.json`. The hook blocks the agent from writing it,
  but Claude Code's own UI process can still write it and it will apply on
  the next session. Put allow rules in `devenv.nix` instead.
- Project allow rules wait for the folder trust dialog in interactive
  sessions; `claude -p` trusts the folder automatically.
- Claude Code rewrites `~/.claude/settings.json` when you switch `/model` or
  modes. The hook compares the jail's keys against
  `/etc/claude-code/jail-settings.json` and ignores `defaultMode`; if any of
  those keys drifts, every tool call fails with `"worker without a jail"`
  until you run `sudo -u w-acme -i aj bootstrap --no-root --yes`.
- claude.ai connectors and account-synced skills/plugins are disabled for
  workers by default. Set `ai-jail.allowConnectors = true` in a repo's
  `devenv.nix` or `allowConnectors = true` in `host.nix` if you need them.
- Settings keys were last checked against Claude Code `2.1.296` and run live
  on `2.1.309`. Unknown or renamed keys are ignored silently by Claude Code,
  so check the settings reference and run `aj check` after upgrading.

## If something goes wrong

Run `aj doctor` as yourself and as the worker; it prints what is missing and
exits `1`. When a session hits a wall, it will look like one of three things
(all three are expected): an `env-guard: ... blocked` line from the hook, a
permission denial naming a rule like `Bash(git push *)`, or a bubblewrap
sandbox error (`Operation not permitted` or a refused host). See the
troubleshooting section in `docs/runbook.md` for everything else.
