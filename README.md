# claude-harness

Project-scoped, guard-railed Claude Code for NixOS. One module set, one
deployment shape: managed settings at `/etc/claude-code`, root-owned, on
every host. Configuration decides how far they reach.

| Host | Configuration | Status |
|---|---|---|
| NixOS-WSL distro (work) | `enforcementRoots = []`, strict network allowlist | module ready, untested on WSL |
| Native NixOS laptop (personal + work repos) | `enforcementRoots = [ "~/code/git" ]`, prompt for unknown hosts | in use |
| macOS (nix-darwin) | managed settings under `/Library/Application Support/ClaudeCode/` | not started |

Containers as the main route were tried and dropped (podman inside
vscode-fhs, double sandbox, no gain over the brief's threat model).
`devenv/` is the project side instead: every repo imports it, and a
per-project image stays available as an opt-in.

Operating it: `docs/runbook.md`. What is next: `docs/roadmap.md`.

## Layout

```
lib/        pure Nix: deny rules (universal + project), managed/project settings, managed-tree packaging
hooks/      env-guard.sh (the one managed hook), tmux-notify.sh
nixos/      NixOS module: harness.* -> /etc/claude-code
home/       home-manager module: devenv, direnv, tmux, programs.claude-code, `ccode`
devenv/     devenv module (devenv/devenv.nix) every repo imports: generates .claude/settings.json, checks the host, optional image
pkgs/       ccode launcher, direnv >= 2.38 override
tests/      hook-test.sh (env-guard.sh unit tests), ccode-test.sh (project resolution)
docs/       runbook (daily flow, onboarding, verification, troubleshooting), roadmap
```

## Enforcement layers

Each Claude Code mechanism covers a different surface, so all are used:

1. Managed settings (root-owned): deny rules, sandbox, every hook, mod
   policy. Nothing in `~/.claude` or a repo can relax them.
2. `permissions.deny`: prefix/glob matching, all modes, final against
   user-tier mods because the managed settings make the built-in guard load.
   Cannot be scoped by directory, so with `enforcementRoots` set the managed
   copy carries only the universal rules; the repo template's
   `.claude/settings.json` carries the full set.
3. `env-guard.sh` PreToolUse/ConfigChange hook: normalised whole-command
   regex (`bash -c`, `env`, `git -C`, quoted words), config-file edit block,
   shell-side config writes, settings-change block. Sees `cwd`, so project
   rules apply only under the enforcement roots. `onFailure: block`.
4. Bash sandbox (bubblewrap): filesystem and egress confinement for
   everything `az`, `terraform`, `tflint`, `trivy` do at runtime. Works
   nested inside `vscode-fhs`.
5. Mod policy: only mods from the root-owned marketplace load; sideload
   flags rejected.
6. Azure RBAC: a Reader-only identity per customer (outside this repo).

Universal rules (everywhere): credentials, `sudo` and system changes,
plugin loading, Windows executables, the user's own Claude/Nix/shell config.
Project rules (under the roots): git history writes, cloud writes, project
config and env files, the SSH agent and key files.

## Usage

```nix
# flake.nix of your NixOS configuration
inputs.harness = {
  url = "github:raul-korhonen/claude-harness";
  inputs.nixpkgs.follows = "nixpkgs";
};

# NixOS
imports = [ inputs.harness.nixosModules.harness ];
harness.enable = true;                       # platform auto-detects wsl vs linux
harness.enforcementRoots = [ "~/code/git" ]; # omit on a dedicated work host
harness.sandboxStrictAllowlist = false;      # omit on a dedicated work host
harness.allowMemoryEdits = true;             # personal machine only: Claude keeps its auto-memory

# home-manager
imports = [ inputs.harness.homeModules.harness ];
harness.enable = true;
```

While changing the harness itself, build the host from a checkout instead
of the locked revision:
`nixos-rebuild switch --override-input harness path:/path/to/claude-harness`.

```yaml
# a repo's devenv.yaml
inputs:
  harness:
    url: github:raul-korhonen/claude-harness   # or path:/path/to/claude-harness while developing
    flake: false
imports:
  - harness/devenv
```

The devenv module writes the repo's `.claude/settings.json` (full deny set
and SSH sandbox rule, read-only symlink into the store) at every shell entry and warns if the host
has no managed settings. Personal repos outside the enforcement roots simply
do not import it.

## Git over SSH

Agents never push; you do, from your own tmux window or editor terminal.
Both run as the same user, so the key has to be unusable for a session
without being unusable for you. Two kinds of key do that, pick one per
machine; both need you present for every signature.

**Hardware key, recommended.** A FIDO2 token (YubiKey, Nitrokey, SoloKey).
The private key never leaves the token, every signature needs a touch, and
with `verify-required` a PIN too. The key handle may live in an agent: an
agent cannot touch the token for anyone. There is nothing on the machine to
steal, so even a session that escaped the sandbox could not sign.

```
ssh-keygen -t ed25519-sk -O resident -O verify-required -C "$USER@$(hostname)"
```

`-O resident` keeps the key on the token, so another machine gets it back
with `ssh-keygen -K`. The passphrase prompt may be left empty: the token and
PIN are the protection. GitHub, GitLab and Codeberg all accept `-sk` keys.

**Passphrase key, fallback.** For hosts and people without a token. The
passphrase is the protection, so it is asked on every use and the key is
never cached in an agent. A session has no terminal to answer the prompt,
which is what makes the key useless to it.

```
ssh-keygen -t ed25519 -a 100 -C "$USER@$(hostname)"
```

Choose a real passphrase at the prompt. Never pass `-N`: it puts the
passphrase in shell history and process lists. Then keep ssh away from every
agent for the hosts that use this key, in `~/.ssh/config` or
`programs.ssh.matchBlocks`:

```
Host github.com
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  IdentityAgent none
```

`IdentityAgent none` is the line that matters. Desktop keyrings (GNOME and
COSMIC's gcr, KDE) run an agent that loads keys from `~/.ssh` on first use
and offers to remember the passphrase; with this line ssh never asks them.
Never set `AddKeysToAgent yes` for this key. Check with `ssh-add -l`: the
passphrase key must not be listed. If it is, `ssh-add -d ~/.ssh/id_ed25519`
removes it, and a remembered passphrase is cleared with
`secret-tool clear unique "ssh-store:$HOME/.ssh/id_ed25519"` (package
`libsecret`).

**Register the public key** (`id_ed25519_sk.pub` or `id_ed25519.pub`).
Print it, paste it under GitHub Settings, SSH and GPG keys, New SSH key
(Codeberg and GitLab: Settings, SSH keys), then test:

```
cat ~/.ssh/id_ed25519.pub
ssh -T git@github.com
```

With the GitHub CLI installed, `gh ssh-key add ~/.ssh/id_ed25519.pub` does
the paste (it needs the `admin:public_key` scope: `gh auth refresh -s
admin:public_key`). Nothing here requires it.

**What to expect.** Every push asks: a touch (and PIN) for the hardware key,
the passphrase for the software key. A push that goes through silently means
the key is cached somewhere; see the `ssh-add -l` check above.

**In a harness repo** the sandbox also strips `SSH_AUTH_SOCK` from every
agent command and hides `~/.ssh`, so a session there cannot even reach the
hardware key's handle. The repo's `.claude/settings.json` carries the rule
(`lib/ssh-sandbox.nix`); managed settings carry it too on a host that
enforces everywhere. A session that runs `git push` there gets
`Permission denied (publickey)`; sessions clone over HTTPS.

## Tests

```
nix flake check            # hook unit tests (both managed trees) and ccode resolver tests
nix build .#managed-scoped # a managed tree to inspect: result/managed-settings.json
```

Hook tests run without Claude Code: they feed hook JSON on stdin and check
the exit code. Add a case per hard limit you rely on.
