# The project devenv

For whoever looks after a jail and has not used Nix. Every repo
under the jailer gets its tools from a devenv shell: direnv enters it
when you `cd` into the repo, and the same shell wraps every Bash command
Claude Code runs there. `aj init` writes the files below, and you
change one of them, `devenv.nix`, when the project needs something new.
Everything below is a change to `devenv.nix` or `devenv.yaml`.

## The files

| File | What it is | Who edits it |
|---|---|---|
| `devenv.nix` | The project's tools, toolchains, environment variables and ai-jail options | you, by hand; an agent proposes the diff |
| `devenv.yaml` | Where the inputs come from (ai-jailer, nixpkgs), plus `allow_unfree` | you, rarely; `aj init --force` rewrites it |
| `devenv.lock` | The exact revision of every input, nixpkgs included. Commit it | nobody: `devenv update` writes it |
| `.envrc` | Makes direnv load the shell, ask before loading changes, and refuse a `devenv.local.*` (below) | nobody: `aj init --force` rewrites it |
| `.claude/settings.json` | The project layer of the rules Claude Code runs under (your allow rules, extra deny rules and hosts, the repo's protected paths), generated at every shell entry, gitignored; absent with the guard rails off (below). The deny rules, hook and sandbox come from the host's managed settings, not from this file | nobody; edits are overwritten |

There is no per-developer file beside them. devenv imports a
`devenv.local.nix` or `devenv.local.yaml` without a `direnv allow`, so
the `.envrc` refuses to load while either exists (`error: devenv.local.nix
is refused in a jail`): remove it and `direnv reload`, or move
its content into `devenv.nix`.

## How a change lands

The same four steps, whatever the change:

1. An agent that needs a tool or a rule proposes the diff to `devenv.nix`
   and stops: the hook refuses its edits to these files and the shell
   commands that write them. You can also write the change yourself.
2. You apply it in your editor and read it: this file runs as the repo's
   Linux user (the worker, `w-<org>`), outside any sandbox, at the
   next shell entry. Edit it as yourself through the worker's group or as
   the worker (`sudo -u w-<org> -i`).
3. `direnv allow` in the repo, as the worker: the hook refuses `direnv
   allow` to a session, so it is yours to run. `.envrc` ends with `require_allowed
   devenv.nix devenv.yaml devenv.lock`, so after a change to any of the
   three direnv says they `require approval` until you do. It flags, it
   does not block: the shell loads the new content either way (runbook,
   troubleshooting), so read a change before you allow it, one a `git
   pull` brought included. In VS Code, mkhl.direnv asks the same
   question. A changed `.envrc` is different: it does not load at all
   until `direnv allow`, and every Bash command a session runs is refused
   with `fix: direnv allow <repo>` until then.
4. Commit `devenv.nix` (and `devenv.lock` when it moved). The agent never
   commits.

The first load after a change downloads or builds what is new, seconds
to minutes; after that it is instant.

## Adding a tool

```nix
  packages = [
    pkgs.git
    pkgs.jq
    pkgs.azure-cli
    pkgs.opentofu
  ];
```

The name after `pkgs.` is the package's attribute name. Find it at
<https://search.nixos.org/packages> (channel "unstable"; the "Name"
field, which is not always the command's name: `az` is
`pkgs.azure-cli`), or with `devenv search <word>` in the repo. The
version is whatever the locked nixpkgs carries; `az version` or
`<tool> --version` in the shell says which. `devenv update` moves
nixpkgs and every tool with it, then step 3 above again.

A package marked unfree (Terraform since 1.6, VS Code, Claude Code) fails
the load with an "unfree" error until `devenv.yaml` says:

```yaml
allow_unfree: true
```

## A language toolchain

devenv bundles the usual set for a language behind one line:

```nix
  languages.rust.enable = true;       # rustc, cargo, clippy, rustfmt, rust-analyzer
  languages.python.enable = true;
  languages.javascript.enable = true; # node and npm
```

These take the versions nixpkgs carries. A pinned version (a Rust
channel, a Python minor) needs one more input in `devenv.yaml`; the
language's page under <https://devenv.sh/languages/> has the lines.

The package manager is the other half. cargo, pip and npm download from
hosts the sandbox does not allow by default, so a session's `cargo
build` fails on the network until the project allows them (below):
`index.crates.io` and `static.crates.io` for cargo, `pypi.org` and
`files.pythonhosted.org` for pip, `registry.npmjs.org` for npm. Tools
from `packages` need none of this: Nix fetches them outside the sandbox.

## Environment variables

```nix
  env.ARM_TENANT_ID = "00000000-0000-0000-0000-000000000000";
  env.ARM_SUBSCRIPTION_ID = "00000000-0000-0000-0000-000000000000";
  env.TF_VAR_environment = "dev";
```

Exported into your shell and every command a session runs. Identifiers
only: `devenv.nix` is committed and the agent reads it. Secrets stay in
`.env` or your `az login` session, which the agent never sees (README,
"Where project configuration goes", has the split and why).

## Project allow rules

A command the project runs all the time can skip the permission prompt:

```nix
  ai-jail.settings.permissions.allow = [
    "Bash(terraform plan *)"
    "Bash(cargo test *)"
  ];
```

The syntax is Claude Code's permission rules (`Bash(<command> *)`, `Read(<path>)`,
...). An allow rule only skips the prompt; it never opens what a deny
rule, the hook or the sandbox refuses, so a refused command stays refused
however it is allowed here. The rules apply to everyone who uses the
repo.

To refuse more, add to the jailer's list instead of replacing it:

```nix
  ai-jail.extraDeny = [ "Bash(az devops *)" ];
```

Never set `ai-jail.settings.permissions.deny` or a list under
`ai-jail.settings.sandbox`: `ai-jail.settings` is merged into the
generated file key by key, and a list there replaces ai-jailer's own,
the full deny set or the network allowlist with it. `extraDeny` and
`extraAllowedDomains` are the options that add.

## Network hosts for the sandbox

Every Bash command a session runs reaches only the hosts on the sandbox's
allowlist: the Azure and Terraform endpoints, GitHub, and the container
registries trivy uses. Anything else fails with a connection error naming
the host. A project that needs more lists them:

```nix
  ai-jail.extraAllowedDomains = [ "dev.azure.com" "index.crates.io" "static.crates.io" ];
```

Whether a managed sandbox honours a repo's list, merges it with the
managed base list or ignores it is not settled: check V2 in the runbook
(section 5) is pending as of 2026-10-27. Until it has run, treat this
option as unconfirmed, and expect to put the host in the host-wide
`extraAllowedDomains` of the ai-jailer checkout's `host.nix` if it turns out
to be ignored. Hosts not on either list prompt in an interactive session and are
refused in a `-p` one.

## The other ai-jail options

The `devenv.nix` `aj init` writes lists every option, the unused
ones commented out; `devenv/devenv.nix` in the jailer has the full
descriptions.

| Option | What it does |
|---|---|
| `enable = false` | the guard rails off for this repo (next section) |
| `readFence`, `extraAllowRead` | hide the rest of `$HOME` from sandboxed commands, and say what the project still reads there |
| `allowConnectors` | the claude.ai account's connectors load in this repo's sessions |
| `platform = "wsl"` | hide `/mnt/c` and `/run/WSL` from the sandbox; `aj init` sets it on a WSL host |
| `claudeCode.enable` | Claude Code's CLI, tmux and jq from this shell, for `ajmux` and tmux sessions on a host with no `claude` of its own (default false); needs `allow_unfree: true`. `aj init` turns both on when it finds no `claude` on the host's `PATH`; with one there, it leaves them commented out |
| `extraDeny`, `extraAllowedDomains`, `settings` | add deny rules, sandbox hosts and allow rules (above) |
| `managedSettingsPath` | where the host keeps the managed settings (`/etc/claude-code/managed-settings.json`); every shell entry warns when it cannot be read |

Whether agents may commit locally, whether Claude keeps its auto-memory
and the account's connectors by default are host decisions now
(`allowLocalCommits`, `allowMemoryEdits` and `allowConnectors` in the NixOS
module); a repo no longer sets the first two.

## Turning the guard rails off (and on)

A repo that should not run under the guard rails turns them off with one
line in `devenv.nix`. One that `aj init` wrote since 2026-10-24 has
it, commented out, first in the `ai-jail = { ... }` block: remove the
`#`. In an older one, add it there:

```nix
  ai-jail = {
    enable = false;
  };
```

Outside that block the same line is `ai-jail.enable = false;`. Then
`direnv allow` in the repo (step 3 above). From the next shell entry:

- `.claude/settings.json` is gone: devenv removes the link it wrote
  before (if one is still there after the next `cd`, delete it by hand).
  Sessions started in the repo lose the project layer only: your allow
  rules, extra deny rules and hosts, and the literal protected paths. The
  host's managed settings (deny rules, hook, sandbox) still apply.
- Every shell entry says so: `ai-jail: guard rails off for this repo
  (ai-jail.enable = false in devenv.nix)`.
- The tools stay: `packages`, toolchains, `env.` variables, `ajmux`, and
  Claude Code itself with `claudeCode.enable`. The other ai-jail options
  stay in the file and do nothing until the rails are back on.
- `aj init` on the repo reports `off` after the first shell entry
  and checks nothing; `aj check` says it is not a jail.

A session that was already open may keep what it loaded: start new
ones after the change, either way.

An agent cannot flip the switch. It is a line in `devenv.nix`, and the
deny rules and the hook refuse an agent's edits to that file (step 1
above), as for every other line in it; one that could write the file
could already loosen the rules through `ai-jail.settings`, so the switch
opens nothing new. A change to `devenv.nix` you did not make still shows
up as `require approval` at the next `cd`.

To turn them back on, delete the line (or write `enable = true;`, the
default) and `direnv allow`. The next shell entry writes
`.claude/settings.json` again; start new sessions.

Committed, the switch applies to everyone who uses the repo. There is
no per-developer form: a `devenv.local.nix` stops the shell from loading
("The files" above).

This only turns off the repo's project layer. The managed settings under
`/etc/claude-code` are root-owned: their deny rules, hook and sandbox apply
in this repo whatever `devenv.nix` says. On a host with no managed file
nothing applies at all, and the shell warns at every entry.

## When the shell does not load

- `require approval` is not this: the shell loaded; step 3.
- `.envrc is blocked`: `direnv allow`, after reading the `.envrc`.
- An evaluation error after an edit: `devenv shell` in the repo prints it
  with the line. A missing `;` or `]` is the usual one.
- `undefined variable` or `attribute ... missing` for a package: the
  name is not the attribute name; search again.
- `unfree`: `allow_unfree: true` in `devenv.yaml`.
