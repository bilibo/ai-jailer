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
[bilibo/nixos-wsl](https://github.com/bilibo/nixos-wsl) and on Fedora, with
two workers.

## Where things are

- `lib/deny-rules.nix`, `lib/settings.nix` and `hooks/env-guard.sh`: the
  rules. The Nix files define what everyone is refused, what a worker is
  refused on top, and what the bubblewrap sandbox hides; `env-guard.sh` is
  the PreToolUse hook that runs outside the sandbox before every tool call
  and actually says no. `lib/claude-defaults.md` is the `CLAUDE.md` every
  session on the host loads first. Read these for the spirit of the project.
- `devenv/devenv.nix`: what a governed repo imports. It writes a read-only
  `.claude/settings.json` from the `ai-jail.*` options on every shell entry.
- `pkgs/`: `aj` (`bootstrap`, `doctor`, `init`, `check`, `upgrade`, `reset`),
  `ajmux` (the tmux launcher that hands over to the worker), and the tmux
  and direnv configs. `scripts/install.sh` puts Nix on a host that lacks it,
  then runs `aj bootstrap` for the host and `aj init` on the checkout.
- `docs/runbook.md`: the operator's reference: host configuration,
  verifying, upgrades, troubleshooting, the limits of the boundary.
  `docs/project-devenv.md`: a practical guide to customizing a
  repo's `devenv.nix` (packages, languages, env vars, allow rules) without
  needing to know Nix first.

## Install

Three steps on any Linux with git and sudo: the host, then the workers,
then a repo per worker.

```sh
git clone https://github.com/bilibo/ai-jailer.git ~/code/ai-jailer
cd ~/code/ai-jailer
scripts/install.sh                          # --check prints the plan and changes nothing
```

`install.sh` installs Nix where it is missing (Fedora's own packages on
Fedora 44+, `nix-installer` elsewhere, nothing on NixOS), runs
`aj bootstrap` for the host (the devenv cache in `nix.conf`, the
user-namespace setting the sandbox needs, and `/etc/claude-code` linked to
the host rules) and `aj init` on this checkout so its devenv shell exists.
From then on `aj` is on PATH in a new terminal through `profile.d`, and in
this checkout's shell (`direnv allow` here, or `devenv shell`). Every step
checks before it writes, so a second run is a no-op.

Workers come next, from this checkout's shell, when you know what to call
them:

```sh
cd ~/code/ai-jailer && devenv shell
aj bootstrap --workers acme,globex          # --dry-run shows the plan and changes nothing
aj doctor
```

That creates a user and group per worker with a `0750` home, puts you in
those groups, enables systemd linger, writes one sudoers rule (you to the
workers, never the other way), and sets each worker up with direnv, devenv,
tmux and a git identity. Run it again with another name to add a worker
later. The third step, `aj init` on a repo, is under "Using it".

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

Initialize a repo under the worker:

```sh
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

The worker's first `ajmux` launch asks for a Claude login in the tmux
window: sign in there with the account for that org's work. The token lands
in the worker's own `~/.claude`, never in yours. Make that first launch an
interactive one; `-p` has no prompt and fails until the worker is signed in.

Each terminal gets its own grouped tmux view of the project's windows, so
multiple VS Code tabs attached to the same project do not follow each other
around. The window tab turns orange when the agent stops or waits on a
prompt.

Agents stage, diff and branch; you review as the worker
(`sudo -u w-acme -i git -C ~w-acme/code/git/acme/infra diff --cached`), and
the commit and push are yours. Workers have no SSH keys or tokens, so they
cannot push. Since your account is the only one on the box with a push key,
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
caught by the hook like `.env` itself. A sandboxed dev server that binds a
port needs Claude Code's `allowLocalBinding`, which nothing here sets.

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

`nix flake check` runs the test suites without Claude Code; `aj check`, as
a worker, runs the live suite: twenty-odd `claude -p` sessions judged on
what they did on disk and in the transcript (runbook section 5).

## If something goes wrong

Run `aj doctor` as yourself and as the worker; it prints what is missing and
exits `1`. When a session hits a wall, it looks like one of three things,
all expected: an `env-guard: ... blocked` line from the hook, a permission
denial naming a rule like `Bash(git push *)`, or a bubblewrap sandbox error
(`Operation not permitted` or a refused host). `docs/runbook.md` has the
rest.
