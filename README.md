# ai-jailer

ai-jailer, or `aj` among friends: guard rails for Claude Code on a
Linux host with Nix. The hard rules (deny rules, a fail-closed hook,
the Bash sandbox, mod policy) live in the host-wide managed settings
under `/etc/claude-code`, root-owned, so no repo file, user setting or
session can relax them. Each customer's agents run as their own Linux
user (`w-<customer>`) with a private home, their own Claude login and
no push credential or sudo; you drive them from your own account with
`ajmux <customer>/<repo>`. A repo's `devenv.nix` adds a project layer on
top (allow rules, extra deny rules, extra network hosts). Agents stage
and diff; you commit and push. Your own sessions are bound by the managed
file too: the rules are the host's, not a repo's.

Status, 2026-10-27: this is the shape the code now has. None of it has run
live yet; the first-run checks are pending (runbook section 5), and the
"Tested" column says only what was exercised.

| Host | Route | Tested |
| --- | --- | --- |
| Any Linux: Fedora 44 or newer, Ubuntu, NixOS, NixOS-WSL, other | One route, run from this checkout's devenv shell ("Usage" below): `aj bootstrap --workers <a,b> [--owner <login>]` links `/etc/claude-code`, creates the worker users, groups and linger, the sudo rule (not on NixOS: the owner's own sudo serves), and sets each worker up as that user. `scripts/install.sh` runs the same after putting Nix on a host that lacks it. NixOS differs in what bootstrap may write: `nix.conf` and the user-namespace sysctl are the system configuration's and are printed as options; the users come from `useradd` (`users.mutableUsers`, the default) | The previous shape (repo file only, one user) ran end to end on Fedora 44 and Ubuntu 26.10 laptops (2026-10-22). The worker route and the NixOS route are covered by the stubbed-host tests only; `nix build --out-link /etc/claude-code` as root is untested |
| macOS (nix-darwin) | managed settings under `/Library/Application Support/ClaudeCode/` | not started |

A host without the managed file enforces nothing: a repo that imports the
devenv module warns at every shell entry, and `aj doctor` reports the
file as MISSING. The earlier routes (a repo file only; the NixOS module
with `harness.owner` and `harness.workers`, dropped 2026-10-27) are gone:
a host configuration carries nothing of ai-jailer.

`devenv/` is the project side: every repo imports it. A container route
was built and set aside; it lives in the claude-nix-harness-container repo,
whose README has what works and what was never verified.

Operating it: `docs/runbook.md`. What is next: `docs/roadmap.md`. What
changed when: `docs/changelog.md`. How sessions coordinate without trusting
each other (tiers and proposals): `docs/sessions.md`. Changing a project's
tools, variables and rules without knowing Nix: `docs/project-devenv.md`.

## Layout

```text
lib/        pure Nix: deny rules, settings.nix (the managed body and the repo's project layer), hooks packaging, managed-tree packaging
hooks/      env-guard.sh (the guard hook), tmux-notify.sh
devenv/     devenv module (devenv/devenv.nix) every repo imports: generates the project layer of .claude/settings.json
host.nix    optional, gitignored: this host's managed-tree options (extra deny rules, domains, the memory and commit switches); flake.nix merges it into `packages.managed`
pkgs/       ajmux launcher, direnv.toml and tmux.conf (the host-side settings), claude-code override (nixpkgs' package without the `LD_LIBRARY_PATH` every command would inherit), devenv-cache.nix (the devenv cache key), the `aj` CLI (aj.nix; bodies under aj/: bootstrap.sh for bootstrap, upgrade, doctor and reset, init.sh, check.sh)
scripts/    install.sh: the one install route on Linux; what must happen before Nix exists (Fedora's packages, or the nix-installer), then `aj bootstrap` with the worker flags, then `aj init` on the checkout
tests/      hook-test.sh (env-guard.sh unit tests), project-settings-test.sh (the generated repo file, plain and fenced), ajmux-test.sh, host-config-test.sh, install-test.sh and aj-bootstrap-test.sh (the install route with stubbed hosts), aj-doctor-test.sh, aj-init-test.sh, managed-tree-test.sh (the mod policy: no marketplace directory, the keys that refuse mods), claude-code-test.sh (the override: wrapper, binary untouched, `--version`; unfree, so only when the evaluator allows it), check-parser-test.sh (`aj check --parse` against the transcripts in fixtures/)
docs/       runbook (daily flow, onboarding, verification, troubleshooting), project-devenv (a project's devenv.nix for non-Nix users), roadmap, changelog, sessions (tiers, proposals), suggestion (ideas with a shape, not planned)
```

## Any Linux: the install script

Needs git and sudo, and curl off Fedora. Previously tested on Fedora 44 and
Ubuntu 26.10 without the worker flags; any other Linux goes through the
same nix-installer route as Ubuntu and should work.

```sh
git clone https://github.com/bilibo/ai-jailer.git ai-jailer
cd ai-jailer
scripts/install.sh --workers acme,globex     # --owner defaults to $USER; --owner-sudo nopasswd|password|none
scripts/install.sh --check --workers acme    # prints the planned steps, changes nothing
```

The script installs Nix where it is missing, then `aj bootstrap` runs
the root steps (devenv cache in `nix.conf`, user namespaces, the managed
link `nix build <ref>#managed --out-link /etc/claude-code`, a user and
group per worker, 0750 homes, linger, the sudoers file checked with
`visudo -cf`), then sets up each worker as that user (direnv, tmux, the
code root, a git identity) and the owner's own profile. It says what it
did, and running it again installs nothing twice. On Ubuntu 23.10 and
later AppArmor confines user namespaces; bootstrap offers the bwrap
profile from the Claude Code sandboxing docs (`/etc/apparmor.d/bwrap`)
and, until it is in place, every Claude command is refused.

Afterwards: `aj doctor` reports the managed file, the managed hook,
the `agents` members, linger and the sudoers file per worker, and whether
the caller is a worker, the owner or neither. `aj upgrade` moves the
profile and the managed link to this checkout's `flake.lock` after a `git
pull`. `aj reset` removes the sudoers file, the managed link and
linger; it keeps the worker users, whose homes hold repos and a Claude
login, and prints the `userdel -r` lines for you to run.

Another project that imports `ai-jailer/devenv` gets the same shell contents
with `ai-jail.claudeCode.enable = true` in its devenv.nix (default false)
and `allow_unfree: true` in its devenv.yaml; `aj init
<customer>/<repo>` writes one and does its first shell entry. On a host
with no `claude` of its own init writes both lines uncommented, so the
repo's shell brings the CLI, tmux and jq for `ajmux` sessions; with a host
`claude` it leaves both commented out.

## Windows: NixOS-WSL

This repo keeps no Windows installer (since 2026-10-24). A host repo
installs NixOS-WSL; `bilibo/nixos-wsl` is the reference one, and its README
has the installer and its flags. That repo carries nothing of ai-jailer
but `ajmux` and the tmux rules (since 2026-10-27); the rules and the
workers come from `aj bootstrap`, run there as on any Linux ("Usage"
below). Bootstrap detects WSL and links the `managed-wsl` tree, which
hides `/mnt/c` and `/run/WSL` from the sandbox.

What a session gets on WSL is in `lib/settings.nix` (`platform = "wsl"`):
`/mnt/c` and `/run/WSL` hidden and `WSL_INTEROP` stripped, so it can
neither read Windows files nor run Windows executables. The host file
keeps the Windows PATH off the Linux PATH for the same reason, and for
speed. Claude Code on Windows is often the VS Code extension's bundled
binary run over Remote-WSL (nix-ld runs it); a session started that way
as the owner still loads the managed file, and `ajmux` sessions use the
CLI `claude` of the worker's profile or of the repo's shell
(`ai-jail.claudeCode.enable`).

## Enforcement layers

Each Claude Code mechanism covers a different surface, so all are used:

1. Managed settings (`/etc/claude-code/managed-settings.json`, root-owned):
   the full deny set, every hook, the sandbox (with `denyRead` on the
   user's own Claude credentials, `~/.claude.json`, `~/.azure`,
   `~/.config/gh`, `~/.git-credentials` and `~/.ssh`, and the credential
   environment variables stripped), the base network allowlist, the mod
   policy and `syncClaudeAiSkills`/`syncClaudeAiPlugins = false`. Applies to
   every session on the host, the owner's included. Nothing in `~/.claude`
   or a repo can relax it.
2. Linux users: one per customer, a 0750 home, no push credential, no
   sudo. The owner is a member of each worker's group and may run any
   command as a worker (`<owner> ALL=(%agents) NOPASSWD: ALL`); no worker
   is in `trusted-users`, so a worker cannot hand the Nix daemon options.
3. The repo's project layer (`.claude/settings.json`, devenv module,
   read-only store symlink): `extraDeny`, allow rules from
   `ai-jail.settings`, the sandbox belt scalars (`enabled`,
   `allowUnsandboxedCommands = false`, `failIfUnavailable`), the repo's own
   settings, skills, hooks, plugin manifest and `.git` hooks and config as
   literal `denyWrite` paths, `extraAllowedDomains` and, when on, the read
   fence. No hooks and no base deny list: those come from layer 1.
4. `permissions.deny`: prefix/glob matching, all modes. Merges across
   scopes, so no user or local file can remove an entry.
5. `env-guard.sh` PreToolUse/ConfigChange hook, registered from managed
   settings only and applying everywhere: normalised whole-command regex
   (`bash -c`, `env`, `git -C`, quoted words), git history writes, cloud
   writes, system changes, in-repo secrets (`.env`, `.tfvars`, `.tfstate`)
   and the user's own Claude credentials, config-file edits, plugin loading,
   nested `claude`/`ajmux` launch flags, tmux commands other than the
   read-only ones, `direnv allow` and its synonyms (the human approves
   `.envrc` changes). `onFailure: block`.
6. Bash sandbox (bubblewrap, Claude Code's socat proxy): filesystem and
   egress confinement for everything `az`, `terraform`, `tflint`, `trivy`
   do at runtime. Works nested inside `vscode-fhs`. Hosts outside the
   allowlist prompt in an interactive session and are refused in a `-p` one.
7. Mod policy (managed only): no mod loads: ai-jailer ships none (since
   2026-10-24) and the built-in guard refuses every other; no marketplace
   can be added beyond `extraKnownMarketplaces` (none by default); sideload
   flags rejected; `allowManagedHooksOnly` by default.
8. Azure RBAC: a Reader-only identity per customer (outside this repo).

### What the repo file is for

It is the project layer, not the enforcement: a repo adds allow rules,
deny rules and network hosts for its own work, and `aj init` checks
the file and the hook on it. It carries nothing the host needs, so a repo
that turns it off (`ai-jail.enable = false`) keeps the managed rules.
Some limits stay with whoever launches the session:

- `claude --setting-sources user`, `--settings`, `--bare` or a session
  started above the repo skip the repo's project layer; `--plugin-dir`
  loads an unvetted plugin. The managed file still applies, and inside a
  session the hook refuses these flags on a nested `claude`.
- A `.claude/settings.local.json` that exists at session start outranks the
  repo file for scalar keys. The hook refuses a session's write to it
  everywhere; the human can create one.
- Project allow rules wait for the folder trust dialog in an interactive
  session; `-p` treats the folder as trusted.
- With the sandbox on, Claude Code runs Bash commands without a permission
  prompt (`autoAllowBashIfSandboxed`, default true), so the deny rules, the
  hook and the sandbox are the gate, not the prompt.
- The claude.ai account's connectors (Gmail, Drive, Notion, ...) are off
  through `disableClaudeAiConnectors`, which holds from any scope;
  `ai-jail.allowConnectors` turns them back on per repo, or `allowConnectors`
  in `host.nix` per host.

### Lockdown level

What a session gets on a host with the managed file. This describes the
code as of 2026-10-27, not a live run; written against Claude Code 2.1.304,
settings keys last checked against 2.1.296. "Prompted" means the human at
the terminal decides; a `-p` session treats a prompt as a refusal.

| | Managed host |
| --- | --- |
| Enforced | deny rules; the fail-closed hook on every writing tool and settings change; the Bash sandbox with no unsandboxed fallback; bypass mode off; `~/.ssh` and the agent socket hidden; account connectors and account-synced skills and plugins off; the GitHub tokens and Azure secrets stripped from every subprocess (`credentials.envVars`); the repo's own settings, hooks, skills, plugin manifest and `.git` hooks and config as literal `denyWrite` paths; mod policy; a worker cannot read another user's home (0750; untested live) |
| Prompted | network hosts outside the allowlist; edits outside the working directory |
| Open | every unix socket (D-Bus, the display, the secret service; `allowAllUnixSockets`, all-or-none on Linux); reads within the worker's own home and of the rest of the machine except the `denyRead` paths (the read fence, off by default, narrows it); dynamic shell constructs the hook's text rules cannot see (runbook section 8); `/add-dir` |

The glob `denyWrite` entries (`**/...`) have no effect on Linux and stay
for macOS; the repo copy repeats them as literal paths under the checkout
(`repoRoot` in `lib/settings.nix`), and `~/.claude` plus Claude Code's own
protections for the working directory hold as before. Closing the open
items, in order, is the "sandbox hardening" entry of the roadmap.

## Usage

The checkout is the control point, on every Linux. Its devenv shell carries
the `aj` CLI built from the checkout and sets the ai-jailer ref to the
checkout, so the rules linked at `/etc/claude-code`, the CLI and the
workers come from one revision:

```sh
git clone https://github.com/bilibo/ai-jailer.git ~/code/ai-jailer
cd ~/code/ai-jailer
devenv shell                                   # or direnv allow, once bootstrap has put direnv on PATH
aj bootstrap --workers acme,globex        # sudo: /etc/claude-code, the users, groups, linger, the sudo rule; then each worker's user side
aj doctor
git pull && aj upgrade                    # moves the rules, the profile packages and the workers to the checkout's lock
```

The host needs Nix with flakes, the devenv cache in the root `nix.conf`
(bootstrap writes it; on NixOS it prints the `nix.settings` block to add),
`devenv` to enter the shell (`nix run nixpkgs#devenv -- shell` does without
one on PATH), and `bubblewrap` and `socat` for the sandbox. On a host
without Nix, `scripts/install.sh` puts it there first ("Any Linux" above).

NixOS and NixOS-WSL run the same command. What differs is what bootstrap
may write there: `/etc/nix/nix.conf` and the sysctls are the system
configuration's (store symlinks), so the `nix.settings` and
`boot.kernel.sysctl` lines are printed where the host lacks them; no sudo
rule is installed (`/etc/sudoers` has no `@includedir`), so `ajmux` hands
over to a worker with whatever sudo the owner has, password or not; the
workers come from `useradd`, which holds while `users.mutableUsers` is true
(the default): a rebuild with it false removes them, and `aj doctor`
reports a worker the receipt names but the host lacks. The `/etc/claude-code`
link survives rebuilds (NixOS only cleans links into `/etc/static`). A host
configuration carries nothing of ai-jailer; `bilibo/nixos-wsl` takes only
`ajmux` and the tmux rules from this flake.

The host-wide options of the managed tree go into `host.nix` at the
checkout root, gitignored (it is this host's policy, not the jailer's); a
`path:<checkout>` ref, which the devenv shell sets, carries it, the
published `github:` ref never does, and bootstrap says so when it finds one
it cannot use. An attrset, or a function of `pkgs`; every key is an
argument of `lib/managed-tree.nix`, and an unknown one fails the build:

```nix
# host.nix
{
  extraDeny = [ "Bash(az devops *)" ];
  extraAllowedDomains = [ "dev.azure.com" ];
  allowMemoryEdits = false;        # memory is a persistence channel (runbook section 4)
  allowLocalCommits = false;
  allowConnectors = false;
  # allowManagedHooksOnly = true; extraKnownMarketplaces = [ ]; platform = "linux";
}
```

`platform` needs no setting: bootstrap links `managed-wsl` under WSL.

Every repo the jailer should govern, on every host, in the worker's clone:

```yaml
# a repo's devenv.yaml
inputs:
  ai-jailer:
    url: github:bilibo/ai-jailer   # or path:/path/to/ai-jailer while developing
    flake: false
imports:
  - ai-jailer/devenv
```

```nix
# the repo's devenv.nix
ai-jail.settings.permissions.allow = [ "Bash(terraform plan *)" ];  # project allow rules
ai-jail.extraAllowedDomains = [ "dev.azure.com" ];                   # sandbox allowlist; whether a managed sandbox honours it is check V2, pending (runbook section 5)
```

```text
# the repo's .worktreeinclude: `claude --worktree` sessions start in
# .claude/worktrees/<name>, where only the files listed here exist.
.claude/settings.json
```

The devenv module writes the repo's project layer at every shell entry
(read-only symlink into the store). Repos outside the jailer do not
import it. A repo that imports it can turn that layer off with one line in
its `devenv.nix`, `ai-jail.enable = false;`, then `direnv allow`; the
managed rules still apply (`docs/project-devenv.md`, "Turning the guard
rails off (and on)"). Only a human can set it: the deny rules and the hook
refuse an agent's edits to `devenv.nix`.

Each user needs direnv >= 2.38 for `require_allowed` in `.envrc` (the
locked nixpkgs ships 2.38.2; bootstrap checks the minimum), `devenv` on
PATH, and the host `bubblewrap` and `socat` with user namespaces enabled
for the sandbox (`failIfUnavailable` refuses to start a session without
it). Bootstrap's profile step adds direnv, devenv, ajmux and aj from
this flake, pinned by its lock (`nix profile add path:<checkout>#direnv
...` by hand does the same), and `path:<checkout>#claude-code` is the
package when Claude Code itself comes from Nix: nixpkgs' wrapper exports an
`LD_LIBRARY_PATH` that every hook, command and MCP server inherits and that
kills a distro binary loading libasound (`pkgs/claude-code.nix` drops the
variable; the binary is otherwise unpatched, so audio output, which needed
it, does not work; the devenv module uses it). `aj doctor` reports
every host prerequisite, `claude doctor` included, and `aj init
<customer>/<repo>` writes the files above into a repo and runs its first
shell entry. `nix run path:<checkout>#aj -- <command>` runs the CLI
from a checkout outside its shell.

`~/.claude/settings.json` is the user's own and is never a store symlink:
Claude Code writes it itself (`/model`). Whether it needs to exist at all
is open (runbook, check V6).

### Where project configuration goes

Agents never read `.env`: the sandbox mounts it as `/dev/null` and the hook
refuses commands that name it. So split a project's settings by what they
are, not by where a dotenv file would have put them:

| What | Where | Who sees it |
| --- | --- | --- |
| Identifiers the tools need: tenant, subscription, client and resource IDs, region, environment name | `devenv.nix`, `env.ARM_TENANT_ID = "..."` and friends, committed | you and the agent, exported into every command by the devenv shell |
| The same, per developer or not for the repository | nowhere: the `.envrc` `aj init` writes fails the load while `devenv.local.nix` or `devenv.local.yaml` exists, because devenv imports them without a `direnv allow` (roadmap 2.7) | nobody |
| Secrets: client secrets, tokens, passwords | `.env`, loaded into the worker's shell with devenv's `dotenv.enable = true` (direnv's own dotenv loading is off on an ai-jailer host), or the worker's `az login` session | the worker's shell only; the agent's preamble loads an empty file, and `ARM_CLIENT_SECRET`, `AZURE_CLIENT_SECRET` and the GitHub tokens are stripped from its environment either way |

A project that keeps its IDs in `.env` today sees `az` and `terraform plan`
fail inside the sandbox until those lines move to `devenv.nix`.
`docs/project-devenv.md` has the `env.` lines, and tools, toolchains,
allow rules and network hosts the same way.

## Git over SSH

Agents cannot push, by construction: a worker user holds no SSH key and no
token, and the sandbox hides `~/.ssh` and strips `SSH_AUTH_SOCK` from every
command anyway (`lib/ssh-sandbox.nix`). A `git push` from a session gets
`Permission denied (publickey)`; sessions clone over HTTPS.

Your own account is where a key lives, so it is the one place a key can be
misused: prefer a FIDO2 key (`ssh-keygen -t ed25519-sk -O resident -O
verify-required`), whose every signature needs a touch, or a passphrase
key with `IdentityAgent none` for the git host so no desktop keyring caches
it; `ssh-add -l` must not list it. Never pass `-N` to `ssh-keygen`: it puts
the passphrase in shell history.

Open: how a commit staged in a worker's clone reaches the remote. The owner
reads the clone through the worker's group (0750 home) and can run `git`
there with `sudo -u w-<customer> -i`, but that user has no credential to
push with, and the design does not yet say whether the owner pushes from
the worker's clone or fetches the branch into their own. Not tested.

## Tests

```sh
nix flake check              # hook unit tests, the generated repo file, the managed tree, ajmux resolution, the install route with stubbed hosts, doctor and init, the check parser, the NixOS and devenv modules evaluated
nix build .#managed          # a managed tree to inspect: result/managed-settings.json
nix build .#project-settings # the repo's project layer with default options
```

From inside a session run it on a copy of the regular files (`CLAUDE.md`,
"Checks"). Hook tests run without Claude Code: they feed hook JSON on stdin
and check the exit code. `project-settings-test.sh` asserts every layer
the repo file must carry. Add a case per hard limit you rely on.

Live, with Claude Code (runbook section 5 has the from-zero sequence and
the pending first-run checks):

```sh
aj doctor                   # as the owner and as a worker: managed file, hook, users, sudo rule, linger; exit 1 when one is missing
aj init <customer>/<repo>   # as the worker; writes a repo, enters its shell, runs both unit tests on the result
aj check <repo>             # as the worker: seventeen `claude -p` sessions, eighteen as an `agents` member, two more in a fenced repo, one fewer outside tmux; judged on transcripts and files; costs API calls
```
