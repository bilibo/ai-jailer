# Runbook: driving the jailer

Day-to-day operation. The README says what the layers are; this is what
you type and what you should see. Written for the person running it, not
for an agent.

Words used here: the owner is your own login, the human. A worker is the
Linux user `w-<org>` that runs one org's sessions. The managed file is
`/etc/claude-code/managed-settings.json` and the tree next to it, where the
hard rules live.

## 1. Daily flow

1. Start a session for an org's repo from your own terminal:

   ```sh
   ajmux acme/infra                     # first window
   ajmux acme/infra --worktree          # a session that will edit files
   ajmux acme/infra -p "explain the module layout"
   ```

   Run by anyone but `w-acme`, while that user exists, `ajmux` hands over
   with `sudo -u w-acme -i ajmux acme/infra ...` (the name, not a path: the
   worker resolves it under its own code root, `~/code/git` by default). The
   worker's tmux server creates or attaches the session `<org>-<repo>` and
   opens one window named `claude` per call. A worker naming another org's
   repo is refused. `ajmux -n ...` prints the resolution, or the handover
   line, and starts nothing. Each terminal gets its own view of the
   project's windows (a tmux session group): the first terminal the session
   itself, each later one a view `<org>-<repo>-<pid>` over the same windows
   with its own current window, gone when it detaches. So one VS Code tab
   per Claude session works, and the tabs do not follow each other. From
   inside the worker's tmux, `ajmux` moves that terminal to the new window.
   Prefix + `d` detaches and leaves the session running; `exit` in a
   window closes it for every terminal.
   `ajmux` takes `claude` from the PATH, else from the repo's devenv shell
   (`direnv exec <repo> claude`), else stops with a message naming
   `ai-jail.claudeCode.enable`. It exports `XDG_RUNTIME_DIR=/run/user/<uid>`
   when unset, so the worker's devenv, direnv and `tmux-notify.sh` find
   their runtime directory.
2. A shell as the worker, to look around, run `git` or `aj`:

   ```sh
   sudo -u w-acme -i                    # or: sudo -u w-acme -i <command>
   ```

   The sudo rule is `<owner> ALL=(%agents) NOPASSWD: ALL`, so it asks for
   no password unless you chose `--owner-sudo password`; on NixOS there is
   no rule and your own sudo decides. Inside a repo under the worker's code
   root, the project name is optional: `ajmux`, `ajmux --worktree`.
3. Your own session in a repo of your own, or in this checkout, is the
   jailer's: bound by the law alone. The hook refuses a credential read
   (`.env`, `~/.ssh`, the GitHub tokens on disk, your Claude login, your
   `az`, `aws` and `gcloud` logins), `git commit` and `git push`; nothing
   else, and no sandbox. Commit and push
   from your own terminal. It edits `devenv.nix`, `.envrc` and `.claude/`
   like any file. The jail is the workers': a session as `w-<org>` gets the
   full rules.
4. Several objectives at once: one `ajmux` call each. Sessions that edit
   files get `--worktree`; the worktree lives under `.claude/worktrees/<name>`,
   has its own `.devenv/`, and its `.envrc` is auto-allowed only if it is
   byte-identical to the main checkout's (the env hook checks).
5. When a session waits for you, its tmux window turns orange: at the end
   of its turn (`Stop`), at a permission prompt or dialog, and after a
   minute idle (`Notification`); the colour is per user, so the worker's
   server colours its own windows. It clears on your next prompt. If you do
   not see it, the hook is not firing: see troubleshooting.
6. You commit and push. Agents stage (`git add`), diff and branch; the
   commit is yours (`allowLocalCommits` flips that per host). Read a
   worker's staged diff as the worker:
   `sudo -u w-acme -i git -C ~w-acme/code/git/acme/infra diff --cached`.
   Your own git refuses another user's repository (`detected dubious
   ownership`) unless you add it with `git config --global --add
   safe.directory <repo>`. How the commit then reaches the remote: RAU-21.

## 2. What a blocked call looks like

The agent sees one of these, in this order of precedence:

- `env-guard: git history/index write blocked` (or another `env-guard:`
  line): the hook denied it. Final, including against mods.
- A permission denial naming a rule such as `Bash(git push *)`: the deny
  list. Also final.
- A sandbox error (`Operation not permitted`, a refused host): bubblewrap.
  With `allowUnsandboxedCommands = false` there is no retry outside.

All three are expected behaviour. The CLAUDE.md contract tells the agent to
propose a diff or ask you instead of working around it. If an agent keeps
hitting a block for something legitimate, the fix is a project allow rule
in `devenv.nix` (`ai-jail.settings.permissions.allow`), never a looser
managed rule.

The hook judges the command's text, quotes stripped, so a read-only command
that only mentions a refused form is refused too: a `grep` whose pattern is
`sudo -u` or `chmod 444`, a prompt that quotes a blocked command. The
message is the same (`privilege escalation blocked`, `shell write to config
file blocked`). Search for another part of the line; never retry the text.

Every rule applies in every session on the host, inside a jail or not, the
owner's included; there are no enforcement roots and no exempt directory.

## 3. Onboarding a repo

The human does this, as the worker, because the repo belongs to that user's
home and the hook refuses `direnv allow` to a session:

```sh
sudo -u w-acme -i aj init acme/infra      # a new directory under the worker's code root
sudo -u w-acme -i aj init <path>          # an existing repo
```

A worker signs in once, on its first interactive `ajmux` launch: Claude
Code's onboarding prompts for the login in the tmux window, and the token
lands in the worker's own `~/.claude`, one account per org. A `-p` run has
no prompt, so the first launch of a new worker is interactive. There is no
separate login step: `claude auth login` would need the CLI on the worker's
PATH, which a host without a claude of its own only has inside the repo
shell `aj init` sets up. Clone over HTTPS; the worker holds no SSH key.

`aj init` does steps 1 to 5 and 7, then runs section 5's unit tests on the
generated file, with the hook test on the managed hook. `--dry-run` shows
what it would write; existing files are left alone. Before the first
`direnv allow` it prints the files it did not write that the shell entry
runs or trusts (`devenv.yaml`, `devenv.nix`, `.envrc`, and a `devenv.lock`
already there, as the inputs it pins, nixpkgs included) and waits for a
`y`, or `--yes`; a re-run on a repo it set up earlier asks about its own
lock as well. A `devenv.local.nix` or `devenv.local.yaml` stops it before
any `direnv allow` (the `.envrc` it writes refuses to load while one
exists); only a repo that keeps its own `.envrc` gets the file listed and
approved instead. With no managed file on the host init finishes the
settings test, reports the file as MISSING and exits 1: the repo would
enforce nothing. The steps, for doing it by hand or for reading what the
script wrote:

1. `devenv.yaml`: add the `ai-jailer` input (`flake: false`) and
   `imports: - ai-jailer/devenv`. Use a git URL pinned by `devenv.lock`; the
   `path:` form is for developing the jailer itself.
2. `devenv.nix`: project tools, and `ai-jail.settings` for project allow
   rules (`docs/project-devenv.md` has every kind of change). On a host
   without a `claude` of its own, `aj init` sets
   `ai-jail.claudeCode.enable = true` here and `allow_unfree: true` in
   devenv.yaml, which put Claude Code's CLI, tmux and jq in the shell for
   `ajmux`. With a host `claude` it leaves both commented out; the `claude`
   line of its report says which way it went.
3. `.envrc`:

   ```sh
   eval "$(devenv direnvrc)"
   use devenv
   require_allowed devenv.nix devenv.yaml devenv.lock
   ```

   The file `aj init` writes puts a check above these lines that fails
   the load while `devenv.local.nix` or `devenv.local.yaml` exists
   (`pkgs/aj/init.sh` has the text). Never `source_env`, `source_up`,
   or a `whitelist.prefix` in direnv.toml.
4. `.gitignore`: `.devenv/`, `.direnv/`, `.claude/settings.json`,
   `.claude/settings.local.json`, `.claude/worktrees/`, `proposals/`.
   `.ignore`: `devenv.lock`, so a ripgrep-backed search skips the
   tracked lockfile (`.gitignore` cannot hide a tracked file).
   `.worktreeinclude`: `.claude/settings.json`, so a `--worktree` session
   starts with the repo's project layer before devenv regenerates it there.
5. `CLAUDE.md`: the environment contract (the block `aj init` writes; run
   `aj init --dry-run` to see it named) plus project notes.
6. No `.claude/skills/<x>/.claude-plugin/plugin.json` anywhere. A directory
   with that manifest is a plugin.
7. `direnv allow`, twice in a new repo (the first load creates
   `devenv.lock`, the second approves it; troubleshooting has the detail).
   Run it yourself as the worker (`sudo -u w-acme -i`, then `cd` into the
   repo): the hook refuses `direnv allow`, `permit`, `grant` and `edit` to
   a session by text. Then `ajmux acme/infra -p "list the tools on PATH"`
   from your account as a smoke test.

## 4. Host configuration

One shape on every Linux, in two runs. First `scripts/install.sh` from a
fresh checkout: it does what has to happen before `nix run` works (Fedora
44 or newer: Fedora's `nix` and `nix-daemon` packages, the SELinux label
and the daemon socket; any other distro: the nix-installer; NixOS:
nothing), then `aj bootstrap` for the host alone, then `aj init` on the
checkout so its devenv shell exists. Then, from that shell
(`cd ~/code/ai-jailer && devenv shell`, which carries the `aj` CLI built
from the checkout and sets the ref to it), `aj bootstrap --workers ...`
once the worker names are known, and again for each worker added later.
What the host ends up with: the managed tree at `/etc/claude-code` (the
law, the jail, the hooks, and the `CLAUDE.md` every session on the host
loads before the user's and the project's), a user and group per worker, the `agents` marker group holding every worker, the
owner in each worker's group, linger on for each worker, and the one sudo
rule where the host can take one. `install.sh` passes any bootstrap flags
on, so `scripts/install.sh --workers acme` does both runs in one when the
names are already known.

| Host | Set |
| --- | --- |
| Fedora, Ubuntu, NixOS, NixOS-WSL, other Linux | `scripts/install.sh`, then `aj bootstrap --workers acme,globex [--owner <login>] [--owner-sudo nopasswd\|password\|none]` from the checkout's shell. The root steps: devenv cache in the root-owned `nix.conf` rather than making anyone a trusted Nix user (a trusted user can hand the daemon any option); the bwrap AppArmor profile where AppArmor confines user namespaces (Ubuntu 23.10 and later) or the sysctl on an older Debian kernel; `nix build <ref>#managed --out-link /etc/claude-code` (`#managed-wsl` under WSL); `groupadd agents`; per worker `groupadd`, `useradd -m -g w-<c> -G agents -s /bin/bash`, `chmod 0750`, `usermod -aG w-<c> <owner>`, `loginctl enable-linger`; `/etc/sudoers.d/ai-jailer`, accepted only after `visudo -cf`. Then per worker `sudo -u w-<c> -i nix run <ref>#aj -- bootstrap --no-root --yes --jailer <ref>` (a `path:` ref under the owner's home is first prefetched into the store, which a worker can read): profile packages (direnv, devenv, ajmux, aj), `direnv.toml`, tmux config, `~/.bashrc.d`, the code root, and a git identity (default `Claude (<c>)`, `claude-<c>@<host>.invalid`). `--check` (install.sh) prints the planned worker steps and changes nothing. Which hosts have run live, and what has not: RAU-20 |
| NixOS, NixOS-WSL: the differences | `/etc/nix/nix.conf` and the sysctls are the system configuration's (store symlinks): bootstrap prints the `nix.settings` block where flakes or the devenv cache are missing, and the `boot.kernel.sysctl` option where user namespaces are confined, and writes neither. No sudo rule: `/etc/sudoers` has no `@includedir`, so `ajmux` hands over with the owner's own sudo, password or not (`--owner-sudo` is ignored with a note). The workers come from `useradd`, which holds while `users.mutableUsers` is true (the default; nothing here can read the value): a rebuild with it false removes them, and `aj doctor` reports a worker the receipt names but the host lacks. The `/etc/claude-code` link survives rebuilds (NixOS cleans only links into `/etc/static`); a link via `/etc/static` is an older module's and makes bootstrap stop with the fix. Nothing of the jailer goes into the host configuration |

`aj bootstrap` flags: `--no-root`, `--no-profile`, `--trusted-user`,
`--workers a,b`, `--worker x` (repeatable), `--owner <login>`,
`--owner-sudo nopasswd|password|none`, `--code-root <dir>`,
`--jailer <ref>`. Worker names are lower-case letters, digits, `-` and
`_`, starting with a letter. `AI_JAILER_WORKER_PREFIX` changes the `w-`
prefix.

The host-wide options, `allowLocalCommits`, `allowMemoryEdits`,
`allowConnectors`, `allowCloudCli`, `allowManagedHooksOnly`, `extraDeny`,
`extraAllowedDomains`, `extraKnownMarketplaces` and `extraInstructions`
(text appended to the host-wide `CLAUDE.md`; the arguments of
`lib/managed-tree.nix`), go into `host.nix` at the checkout root, an
attrset the flake merges into `packages.managed`; gitignored, reached only
through the `path:<checkout>` ref the devenv shell sets (the README's "Make
it yours" has an example). `allowMemoryEdits` is off by default on purpose:
memory under `~/.claude/projects/<slug>/memory/` is text that every later
session of that user reads as context, so it is a persistence channel for
anything an agent picked up from a repo. With it on, only that directory
opens; the rest of `~/.claude` stays read-only.

`allowCloudCli` is off by default too: the sandbox hides `~/.azure`,
`~/.aws` and `~/.config/gcloud`, so `az`, `aws`, `gcloud`, and Terraform
through them, find no login in a session. With it on, sandboxed commands
run as the login you gave the worker (`sudo -u w-acme -i az login`; a
session cannot log in itself). The Read tool and any command that names one
of the three directories stay refused either way. Give that login a
read-only role before turning it on: section 8 lists what the rules do not
cover. Untried with a logged-in worker (RAU-46); run `az account show` in a
session after `aj upgrade` to see that it took.

In a repo, `devenv.nix` sets `ai-jail.settings` for allow rules,
`ai-jail.extraAllowedDomains`, `ai-jail.extraDeny` and
`ai-jail.allowConnectors` (the claude.ai account's connectors, off by
default: they are MCP servers outside the sandbox). The memory and commit
decisions are the host's, not the repo's.

`ai-jail.enable = false;` in a repo's `devenv.nix` turns off the repo's
project layer: after `direnv allow` there is no `.claude/settings.json`,
every shell entry prints `ai-jail: guard rails off for this repo`, and
`aj init` reports `off` and checks nothing. The managed file still
applies in that repo (`docs/project-devenv.md`).

`~/.claude/settings.json` is each user's own plain file, never a store
symlink: Claude Code writes it itself (`/model`, the mode switch). For a
worker, `aj bootstrap` merges the jail's keys into it and the hook checks
them against `/etc/claude-code/jail-settings.json` before every tool.

Windows: the host repo carries the installer, not this repo;
`bilibo/nixos-wsl` is the reference one, and its README has the install and
update steps. It carries nothing of ai-jailer but `ajmux` and the tmux
rules; the rules and the workers come from `aj bootstrap` run there, which
links the `managed-wsl` tree. The VS Code extension runs its bundled binary
inside WSL, as the owner; the managed file applies to it as well.

## 5. Verifying after a rebuild or a Claude Code upgrade

Read-only checks first, as the owner and as a worker:

```sh
aj doctor                              # as the owner: the managed file, the managed hook runnable, agents members, linger per worker, sudoers (visudo -cf), and which standing the caller has
sudo -u w-acme -i aj doctor            # as a worker: the same, plus the repo report (symlink, direnv allow) and the jail against its reference
```

Exit 1 when something the jailer needs is missing. A missing managed file
is `MISSING: this host enforces nothing`. The `info` lines
`AI_JAILER_CODE_ROOT`, `AI_JAIL_PROJECT` and the caller's standing show which
repo and user the shell is in. `claude doctor` is the Claude Code side:
install health and settings-file validation, without a session.

Live, as the worker, in a worker repo (costs API calls; run it from a
terminal, never from inside a session):

```sh
sudo -u w-acme -i aj check ~w-acme/code/git/acme/infra
```

The path is spelled `~w-acme/...`, never `~/...`: your own shell expands
`~` before `sudo` runs, so a bare `~` names your home and the check stops
at `no such directory`. The same goes for every path after
`sudo -u w-acme -i`.

Around twenty `claude -p` sessions: one more in a fenced repo, one fewer
outside tmux, one fewer in a repo that keeps its own `.envrc`. One login
pre-flight call first, so a worker that never logged in gets one `FAIL
login` naming the fix instead of twenty failures. Judged on the stream-json
transcripts and on the files afterwards, not on the model's prose;
transcripts stay in a temp directory for the exact refusal text. A repo
file whose sandbox is off draws a warning, not a failure. `aj check` runs
the `claude` a terminal in the repo would get: the repo shell's
(`ai-jail.claudeCode.enable`), else the host's; the `claude:` line of its
header, `--dry-run` included, says which.

Transcripts stay under `/tmp/aj-check.*`, from interrupted runs too;
`rm -r /tmp/aj-check.*` when done with them.

After the checks, on a host: `nix config show | grep trusted-users` names
no worker; `git push` as the worker finds no credential; `ajmux
acme/<repo>` from the owner's terminal lands in the worker's tmux and the
window turns orange on a prompt; `aj reset` leaves the users and prints
`userdel -r` lines.

From zero on a Fedora host. `aj reset` reverses what the receipt lists,
the Fedora nix packages included when install.sh put them there; without a
receipt it does nothing ("nothing recorded, nothing to reset"):

```sh
aj reset                                 # sudo; asks first; reads the receipt; keeps the worker users and prints userdel -r for each
scripts/install.sh                       # sudo: dnf, SELinux label, daemon socket; then aj bootstrap (host root steps) and aj init on this checkout
# new terminal: PATH and NIX_SSL_CERT_FILE come from profile.d and ~/.bashrc.d
aj doctor                                # every line ok or info; no workers yet
devenv shell                             # in this checkout
aj bootstrap --workers acme              # the worker user, linger, the sudo rule, the worker's profile
aj doctor                                # the worker lines too
sudo -u w-acme -i aj init acme/infra     # files, two allows, the settings checks, the hook cases
sudo -u w-acme -i aj check ~w-acme/code/git/acme/infra
ajmux acme/infra                         # interactive: trust dialog once, orange window when it waits
```

Log out and in once at the end so GUI-launched VS Code sees the nix profile.

Unit tests, no Claude Code needed, from a checkout of this repo:

```sh
nix flake check                                     # every suite under tests/, in the Nix sandbox
nix shell nixpkgs#jq -c tests/hook-test.sh /etc/claude-code/hooks/env-guard.sh   # the installed hook
tests/ajmux-test.sh "$(command -v ajmux)"           # inside a repo shell, or after aj bootstrap
```

Live checks by hand, inside a jail, as the worker:

```sh
claude -p 'run: grep -i nonewprivs /proc/self/status'      # NoNewPrivs: 1 => sandboxed
claude -p 'run: git commit -m x'                            # env-guard block
claude -p 'run: cat ~/.azure/msal_token_cache.json'         # blocked
claude -p 'run: echo x > devenv.nix'                        # blocked
claude -p 'edit .envrc and add a comment'                   # blocked
claude -p 'run: claude --dangerously-skip-permissions -p hi' # blocked (nested session)
claude -p 'run: which cargo'                                # the devenv one, not system
claude -p hi --debug-file /tmp/d.txt; grep env-guard /tmp/d.txt   # managed hook registered (debug goes to a file)
claude --plugin-dir /tmp/x -p hi                            # rejected at startup
claude -p hi --debug-file /tmp/d.txt; grep -i allowManagedModsOnly /tmp/d.txt   # guard loaded
```

After a Claude Code upgrade also re-read the settings reference for the
keys in `lib/settings.nix`; the file header records the version they were
checked against. Keys that stop existing are silently ignored, which is
the dangerous direction.

## 6. Upgrades and pins

- Claude Code: from a repo shell (`ai-jail.claudeCode.enable`, this flake's
  `claude-code` package) or the native install; `claude update` moves it
  and `autoUpdates` stays off in `~/.claude.json` so an upgrade is a
  decision, followed by `aj check`. Minimum 2.1.295 for `onFailure:
  block`; the settings keys were last checked against 2.1.296
  (`lib/settings.nix` header).
- The managed tree: on every host `aj upgrade` from the checkout's shell,
  after `git pull`, rebuilds `<ref>#managed` and moves the
  `/etc/claude-code` link, re-adds direnv, devenv and ajmux to the profile
  from the current lock, then hands the user steps to the jailer it just
  put in the profile (the running one is the old build). A bare `aj
  upgrade` upgrades the workers recorded in the receipt. `aj bootstrap`
  alone reruns the steps with whatever aj is on PATH. A hook change reaches
  a session only through the managed link, not through the working tree.
- direnv: plain `pkgs.direnv`, >= 2.38 (`MIN_DIRENV` in bootstrap; doctor
  reports an older one) for `require_allowed`.
- devenv from nixpkgs. Each repo pins its own devenv inputs in
  `devenv.lock`; `devenv update ai-jailer` bumps the jailer input in one
  repo.

## 7. Troubleshooting

- **A warning at shell entry that the managed settings are unreadable, or
  `aj doctor` says `this host enforces nothing`.**
  `/etc/claude-code/managed-settings.json` is missing or unreadable:
  `scripts/install.sh` (or `aj bootstrap`) has not run its root steps, or
  `aj reset` removed the link. Until it is back, no rule applies on this host.
- **A worker gets every tool refused with `worker without a jail: ...
  differs from /etc/claude-code/jail-settings.json`.** The worker's
  `~/.claude/settings.json` lost or changed a jail key (an edit, or an
  older bootstrap). `aj doctor` as the worker says the same; `sudo -u
  w-acme -i aj bootstrap --no-root --yes` rewrites it and keeps the
  worker's own `defaultMode`.
- **`sudo -u w-acme -i` asks for a password or refuses.** The sudoers
  file is missing, failed `visudo -cf`, or `--owner-sudo` was `password` or
  `none`. `aj doctor` reports the file; the rule is `<owner>
  ALL=(%agents) NOPASSWD: ALL`. The worker must be in the `agents`
  group, and the owner is the login bootstrap ran as (or `--owner`). On
  NixOS there is no rule: the owner's own sudo applies, password or not.
- **`ajmux` hands over but no tmux server or devenv shell works as the
  worker (`XDG_RUNTIME_DIR` unset, `/run/user/<uid>` missing).** Linger
  is off for the worker, so no user manager runs. `loginctl enable-linger
  w-acme` (bootstrap sets it; `aj doctor` lists it per worker). Use `sudo
  -u w-acme -i`, not a bare `sudo -u`, so the worker's login shell sets its
  own `AI_JAILER_CODE_ROOT`.
- **Agent's tools are the system ones, not the project's.** The env hook
  did not run or direnv is not allowed in that directory. Check
  `direnv status` in the repo, as the worker. The preamble runs
  `direnv export bash` per command. The hook refuses the command instead
  when that export would fail (`env-guard: direnv export failed in <dir>:
  ...`), with the fix in the message; an edited `devenv.nix` that is not
  yet approved loads anyway (`require_allowed` only flags it).
- **`env-guard` refuses `direnv allow`, and its message says `fix: direnv
  allow <repo>`.** The hook refuses `direnv allow|permit|grant|edit` by
  text ("the human approves .envrc changes"), and the `fix:` advice in the
  changed-`.envrc` message points at the command it refuses. Run it
  yourself, as the worker, in a terminal: the advice is for the human, not
  for the session.
- **"sandbox unavailable" at start.** `failIfUnavailable` is on, so the
  session refuses to start. bubblewrap needs user namespaces (on NixOS the
  default; bootstrap prints the `boot.kernel.sysctl` line where a kernel
  confines them) and works nested inside `vscode-fhs`. Inside a container
  it needs `/proc` unmasked.
- **`az`, `terraform plan` or the app fail in a session for want of a
  variable that is in `.env`.** The agent never sees `.env`: the sandbox
  mounts it as `/dev/null` and the hook refuses any command naming it, and
  the rule covers `.env.*` too (`.env.example` included; name a template
  `env.example`). Non-secret values (tenant and subscription IDs, regions)
  go in `env.X` in `devenv.nix`; secrets stay in `.env` for your own shell.
  There is no switch: the rule is host-wide.
- **Every sandboxed command dies with `bwrap: execvp /bin/bash: No such
  file`.** A `Read(...)` deny rule on a directory that holds a symlink into
  the store (`.devenv/`, `.terraform/`): Claude Code merges it into the
  sandbox's `denyRead` and expands the glob through the symlink, putting a
  tmpfs over the target. Remove the rule. `strace -f -e trace=execve`
  around `claude -p` shows the bwrap mounts; `--debug-file` logs nothing
  of the sandbox.
- **Repo hooks or project allow rules do not fire.** The hooks are the
  managed file's and always load. Project allow rules wait in an
  interactive session until you accept the workspace trust dialog for the
  folder; `-p` sessions treat it as trusted. A dangling
  `.claude/settings.json` symlink (store path collected) drops the project
  layer; `direnv reload` rewrites it. Check the hook with `claude -p hi
  --debug-file /tmp/d.txt; grep env-guard /tmp/d.txt`.
- **Plugin or marketplace refused.** `strictKnownMarketplaces` is
  `extraKnownMarketplaces` and nothing else: empty by default, so no
  marketplace can be added. Add the source in `host.nix` on that host, or
  accept that the plugin does not load there. A mod is refused whatever
  the list says: ai-jailer ships none and the built-in guard lets no other
  through.
- **`ai-jail: guard rails off for this repo` at every `cd`.** The repo's
  `devenv.nix` sets `ai-jail.enable = false`. If nobody meant to, `git log
  -p devenv.nix` says who did; delete the line and `direnv allow`. The
  managed rules apply either way.
- **Plugin hooks silent.** `allowManagedHooksOnly` is on. Expected.
- **`.claude/settings.json` is a dangling symlink.** The store path was
  garbage collected; enter the shell again (`direnv reload`) and devenv
  rewrites it.
- **Worktree `.envrc` blocked.** It differs from the main checkout's. That
  is the point; make them identical or allow it yourself after reading it.
- **`git push` from a session fails with `Permission denied (publickey)`.**
  Expected: workers hold no key, and sessions get no agent socket and no
  `~/.ssh`.
- **A push went through without asking** from your own account. Either the
  key is cached in an agent (`ssh-add -l` lists it; `ssh-add -d <key>`
  removes it, and the host block needs `IdentityAgent none`), or the remote
  is HTTPS and a credential helper answered: VS Code's GitHub sign-in when
  you push from the editor, `gh` when it is git's helper. `git remote -v`
  shows which; `git remote set-url origin git@github.com:<org>/<repo>.git`
  puts the key back in the path.
- **`nix-daemon.socket` fails with `Failed to create listening socket ...
  Permission denied` on Fedora.** SELinux: `/nix` is `default_t` without a
  policy and systemd may not create a socket there; auditd has the AVC,
  the journal does not. Label the directory the way the Determinate
  installer's `nix.fc` does, which `scripts/install.sh` does itself:
  `sudo semanage fcontext -a -t var_run_t '/nix/var/nix/daemon-socket(/.*)?'`,
  `sudo restorecon -RF /nix/var/nix/daemon-socket`, then restart the socket.
- **devenv fails with `the SSL certificate is invalid` while fetching an
  input, on Fedora.** Nix-built tools look for the CA bundle at the NixOS
  and Debian path or where `NIX_SSL_CERT_FILE` points, and Fedora 44 keeps
  it only at `/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem`.
  Bootstrap exports the variable in `~/.bashrc.d` (per worker too); a
  terminal opened before it ran lacks it.
- **First `direnv allow` in a new repo ends with `devenv.nix and
  devenv.yaml and devenv.lock require approval`.** Expected: the first
  load created `devenv.lock`. `direnv allow` once more, in the same shell.
- **mkhl.direnv reports that direnv is not found.** VS Code started from
  the menu has the login session's PATH, which lacks the nix profile until
  the next login (`~/.config/environment.d`, written by bootstrap). It also
  sets `direnv.path.executable` in the VS Code settings, which works at
  once; check it points at the profile's direnv.
- **Hook denies everything, including `ls`.** A regex error makes the ERR
  trap fire, which is the fail-closed design. Run the unit tests; the first
  failing case points at the line.
- **`/model` fails with `EROFS: read-only file system, open
  '/nix/store/...-home-manager-files/.claude/settings.json.tmp...'`.**
  home-manager owns `~/.claude/settings.json` as a store symlink and Claude
  Code writes that file itself at user scope. Keep user-scope settings out
  of a Home Manager `programs.claude-code.settings`: the managed settings
  and the jail carry everything the jailer needs.
- **`git config` in a worker repo fails with `could not lock config file
  .git/config: File exists`, and `git status` there lists `.bashrc`,
  `.gitmodules`, `.claude-plugin`, `.vscode` and other empty files nobody
  wrote.** A session was interrupted while a sandboxed command ran (Ctrl-C
  on `aj check`, an aborted tool). The files are bubblewrap's mount points
  for denied paths the repo did not have; Claude Code removes them when the
  command ends, not when it is aborted (RAU-31). Remove them with the
  `find ... -delete` that `aj check` prints when it sees them; the worker's
  home has the same (`~/.gitmodules`, `~/.idea`). Until then `git config`
  fails and a real `.vscode/` or `.claude/hooks/` cannot be created. Nothing
  hides them: an ignore rule for `.vscode` or `.claude/skills` would hide a
  real directory of that name made later.

## 8. Limits of the boundary

- Deny rules and the hook match text. `git -C`, `bash -c`, quoting and
  `env` prefixes are covered by normalisation; a script that opens files
  itself is not. The sandbox and Azure RBAC are the layers for that.
- The sandbox is host-wide and cannot be scoped by directory. What is
  hidden from agents in jails is hidden in every other repo too.
- Settings files reload live, so a repo converted while a session is open
  picks up the project layer; restart the session.
- The hook refuses `.claude/settings.local.json` changes everywhere, which
  is also where "Yes, and don't ask again" writes. The file is still
  written; the new allow rule applies from the next session. Allow rules
  for a project belong in `devenv.nix` (`ai-jail.settings`).
- Hooks run outside the sandbox with the session user's permissions. Keep
  `env-guard.sh` small; it is the one script that must be right.
- The managed file is not tied to a launch: `claude --setting-sources
  user`, `--settings` and a session started above the repo skip the repo's
  project layer, not the managed rules.
- MCP and LSP servers run outside the sandbox and the law does not restrict
  them (no `allowedMcpServers`): a cell may need one, and Claude Code's own
  approval of a project `.mcp.json` is the human's gate (RAU-32).
- `allowCloudCli = true` hands a session the worker's cloud login. The hook
  refuses the logins, the token exports and the well-known secret reads
  (`az account get-access-token`, `az keyvault secret show`, `az storage
  account keys list`, app settings and connection strings; `aws
  secretsmanager get-secret-value`, `aws sts assume-role`; `gcloud auth
  print-access-token`, `gcloud secrets versions access`; hook rule 3 has
  the list) and `az` writes (rule 2). `aws` and `gcloud` writes have no
  rule beyond Terraform's (RAU-47), and a script that calls the API or
  opens the token cache itself passes every text rule. The role on the login is the
  limit: read-only and without secret access (on Azure `Reader`, with no
  Key Vault data role or access policy). A session can also write
  `~/.azure` and `~/.aws`, which the CLIs need to renew a token and which
  hold their configuration; gcloud's directory stays read-only, under
  `~/.config`.

Sandbox limits. Closing them is RAU-22 (tmux socket), RAU-23 (keyring
sockets) and RAU-24 (the read fence):

- tmux is per UID: a worker's server and socket belong to the worker, so a
  sandboxed `send-keys` reaches only that worker's own server. That server
  runs outside the sandbox and its socket is reachable from inside
  (`allowAllUnixSockets`), so a sandboxed `tmux send-keys`, `run-shell` or
  `new-window` still runs unsandboxed and unhooked, as the worker (not as
  the owner). Hook rule 6 refuses the same launch flags after `ajmux` as
  after `claude`, and rule 7 refuses every tmux command but the read-only
  ones; both read command text, so a script talking to the socket still
  gets through. A private socket under a `denyRead` directory is the fix.
- Reads within the worker's own home are open. A sandboxed command reads
  the whole machine the worker's UID can read, except the `denyRead` paths
  (`~/.claude/.credentials.json`, `~/.claude.json`, `~/.config/gh`,
  `~/.git-credentials`, `~/.ssh`, and `~/.azure`, `~/.aws` and
  `~/.config/gcloud` unless `allowCloudCli` is on; `lib/settings.nix` has
  the full list, WSL entries included). Another user's home is closed by
  0750, which `aj check` case 18 tests. The Read tool reaches the same
  files (`blockReadsOutsideWorkingDirectories` is unset).
  `ai-jail.readFence = true` turns on a fence (`denyRead ["~/"]` plus
  `allowRead` for the repo and the shell-entry paths); untried in a real
  cell. The `Read(**/.env)` deny rules do become sandbox `denyRead`: a
  `.env` under the checkout is bind-mounted as `/dev/null` for every
  command, whatever verb reads it; a `.env` outside the cwd tree is not
  fenced.
- Glob `denyWrite` entries do nothing on Linux (`mkdir
  $TMPDIR/x/.claude-plugin` succeeds inside the sandbox; they stay for
  macOS). The repo file repeats its protected paths as literal paths under
  the checkout, which Linux honours; a plugin manifest or hook directory
  elsewhere under `$HOME` is still creatable, and `~/.claude` plus Claude
  Code's own working-directory protections hold.
- Network: `allowedDomains` is the base list plus `extraAllowedDomains`,
  and a cell's list is merged in; an unlisted host
  prompts in an interactive session and is refused in a `-p` one. `"*"`
  opens the network, no prompt.
- Every unix socket is reachable (`allowAllUnixSockets`, all-or-none on
  Linux): the D-Bus session bus, the secret service behind it, the display
  server, not only the Nix daemon and go-plugin. One more reason to keep
  `trusted-users` off (the daemon socket would be root-equivalent). The SSH
  agent is the example: `SSH_AUTH_SOCK` is stripped, but
  `/run/user/<uid>/gcr/ssh` is guessable and answers from inside the
  sandbox; a worker holds no key, so there is nothing for it to sign with.
- The environment: the sandbox's `credentials.envVars` denies the Azure,
  AWS and Google secrets, the SSH agent and the GitHub tokens; every other variable of the
  launching shell is inherited. Name a secret in
  `sandbox.credentials.envVars` through `ai-jail.settings` instead.
- The hook strips quotes before matching, so a quoted string that mentions
  a config path next to something that looks like a write is refused too:
  `echo "settings -> $(readlink .claude/settings.json)"` (the `->`) and
  `ls ~/.claude/.credentials.json | head` are both denied. A secret path
  anywhere in a command is refused unless the command is one harmless verb
  (`ls`, `stat`, `rm`, `wc`, `echo`, ...) with no pipe, substitution or
  input redirection, so `claude -p "why is .env hidden"` is refused too.
  Rephrase.

Text-matching gaps the other layers are meant to catch. Why they are
accepted, and what would reopen them: RAU-32.

- Shell constructs that compute the command at runtime: `$IFS`, `git\ push`,
  `$(echo git) push`, variable indirection, `base64 -d | sh`, python or node
  spawning git. No regex closes these; the sandbox, the absence of push
  credentials inside it and server-side branch protection are the gate.
- GitHub CLI writes (`gh pr merge`, `gh release create`, `gh repo delete`,
  `gh secret set`, `gh gist create`, `gh api -X DELETE`) and package or
  image publishing (`npm publish`, `cargo publish`, `dotnet nuget push`,
  `docker push`). Same policy as `git push`, not encoded.
- Git config keys that run programs: `-c core.hooksPath=`, `core.sshCommand`,
  `credential.helper`, `--config-env`, `git log --output`. The `.git/hooks`
  write block does not cover a hooksPath pointing elsewhere. Writing one
  into the main checkout's `.git/config` fails in the sandbox (the lock
  path is masked: `could not lock config file .git/config: File exists`,
  `aj check` case 15); the `-c` form, `--global` and a worktree's config
  are the accepted gaps.
- `git checkout <path>` with one word (a path cannot be told from a branch
  name) and `git -c alias.x=reset x`, which runs through the `-c` keys. A
  ref followed by paths is refused.
- `az storage blob upload` and other az upload or copy verbs: the az regex
  lists mutation verbs, not transfer verbs.
- Shell writes to your own config (`echo >> ~/.bashrc`, `authorized_keys`,
  `git config --global`): the Edit tool is blocked, the shell path is left
  to the sandbox write allowlist.
- Outbound transfer (`curl -T`, `scp`, `ngrok`, `ssh -R`): the network
  allowlist is the layer.
- The nested `claude` launch-flag rule matches the flag word anywhere in
  the command, quotes stripped, so `claude -p "why is --bare refused"` is
  denied too. Rephrase the prompt.
