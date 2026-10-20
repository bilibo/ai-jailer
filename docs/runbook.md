# Runbook: driving the harness

Day-to-day operation. The README explains what the layers are; this is what
you type and what you should see. Written for the person running it, not
for an agent.

## 1. Daily flow

1. Open the repo folder in VS Code. direnv (`mkhl.direnv`) loads the devenv
   shell; the first time, or after `devenv.nix`/`devenv.yaml`/`devenv.lock`
   change, it asks you to allow. Allow from a terminal:
   ```
   direnv allow
   ```
   The harness devenv module runs at that moment: it writes
   `.claude/settings.json` (store symlink: deny rules, hooks, sandbox,
   bypass mode off). On a host that carries the harness home module it also
   warns if `/etc/claude-code/managed-settings.json` is missing, which
   means the NixOS module is not enabled there; fix the host. An unmanaged
   host runs on the repo file alone and stays quiet.
2. Start a session in the project's tmux session. Inside the repo (any
   subdirectory or worktree) the project name is optional:
   ```
   ccmux                                # first window
   ccmux --worktree                     # a session that will edit files
   ccmux -p "explain the module layout"
   ccmux <customer>/<repo> --worktree   # from anywhere else; a path works too
   ```
   `ccmux` creates or attaches the tmux session named `<customer>-<repo>` and
   opens one window per call. From inside tmux it switches to it; from the
   VS Code terminal it attaches. It resolves the project from the argument,
   else from `HARNESS_PROJECT` (exported by the devenv shell at entry), else
   from the current directory under the code root. `ccmux -n ...` prints the
   resolution without starting anything. `ccode` is the former name and
   still works.
3. Several objectives at once: one `ccmux` call each. Sessions that edit files
   get `--worktree`; the worktree lives under `.claude/worktrees/<name>`,
   has its own `.devenv/`, and its `.envrc` is auto-allowed only if it is
   byte-identical to the main checkout's (the env hook checks).
4. When a session waits for you, its tmux window turns orange. It clears on
   your next prompt. If you do not see it, the Notification hook is not
   firing; see troubleshooting.
5. You commit and push. Agents stage (`git add`), diff and branch; the
   commit is yours. `allowLocalCommits` flips that per host if you change
   your mind.

## 2. What a blocked call looks like

The agent sees one of these, in this order of precedence:

- `env-guard: git history/index write blocked` (or another `env-guard:`
  line): the hook denied it. Final, including against mods on a managed
  host.
- A permission denial naming a rule such as `Bash(git push *)`: the deny
  list. Also final.
- A sandbox error (`Operation not permitted`, a refused host): bubblewrap.
  With `allowUnsandboxedCommands = false` there is no retry outside.

All three are expected behaviour. The CLAUDE.md contract tells the agent to
propose a diff or ask you instead of working around it. If an agent keeps
hitting a block for something legitimate, the fix is a project allow rule
in `devenv.nix` (`harness.settings.permissions.allow`), never a looser
managed rule.

Note the scoping: project rules (git history, cloud writes, project config)
apply when the session's directory, the edited file, or the command text is
under an enforcement root. Universal rules (credentials, `sudo`, system
changes, plugin loading, your own `~/.claude` and `~/.config`) apply in
every session on the host, inside a harness repo or not.

## 3. Onboarding a repo

`harness init <customer>/<repo>` (a new directory under the code
root) or `harness init <path>` (an existing repo) does steps 1 to 5
and 7, then runs section 5's unit tests on the generated file; `--dry-run`
shows what it would write, existing files are left alone. The steps, for
doing it by hand or for reading what the script wrote:

1. `devenv.yaml`: add the `harness` input (`flake: false`) and
   `imports: - harness/devenv`. Use a git URL pinned by `devenv.lock`; the
   `path:` form is for developing the harness itself.
2. `devenv.nix`: project tools, and `harness.settings` for project allow
   rules.
3. `.envrc`:
   ```
   eval "$(devenv direnvrc)"
   use devenv
   require_allowed devenv.nix devenv.yaml devenv.lock
   ```
   Never `source_env`, `source_up`, or a `whitelist.prefix` in direnv.toml.
4. `.gitignore`: `.devenv/`, `.direnv/`, `.claude/settings.json`,
   `.claude/settings.local.json`, `.claude/worktrees/`.
   `.worktreeinclude`: `.claude/settings.json`, so a `--worktree` session
   starts with the repo's rules before devenv regenerates them there.
5. `CLAUDE.md`: the environment contract (copy the block from the test repo)
   plus project notes.
6. No `.claude/skills/<x>/.claude-plugin/plugin.json` anywhere. A directory
   with that manifest is a plugin.
7. `direnv allow`, twice in a new repo (the first load creates
   `devenv.lock`, the second approves it; troubleshooting has the detail).
   Then `ccmux <customer>/<repo> -p "list the tools on PATH"` as a smoke
   test.

## 4. Host configuration

| Host | Set |
|---|---|
| Managed host (NixOS, NixOS-WSL) | NixOS module `harness.enable = true;` and home module `harness.enable = true;`, nothing else; everything strict, everywhere |
| Unmanaged host | No harness modules. Your own config provides direnv >= 2.38 (`pkgs/direnv.nix`), `devenv`, `programs.claude-code`; harness repos import `harness/devenv` and bring their own rules. Sessions outside them keep whatever your own settings allow. Fedora 44 or newer: `scripts/install.sh` installs Fedora's `nix` and `nix-daemon` packages and hands over to `harness bootstrap`, which adds direnv, devenv, ccmux and `harness` from this flake (`nix profile add`) and writes the home module's direnv, tmux and PATH configuration as plain files, plus the user-scope `strictAllowlist`. It puts the devenv cache into the root-owned `nix.conf` rather than making you a trusted Nix user: a trusted user can hand the daemon any option, and agents run as you. `--trusted-user` opts in when a project needs per-repo caches. |
| Mixed host | NixOS module with `enforcementRoots`, `sandboxStrictAllowlist = false`, `allowManagedHooksOnly = false`, `extraKnownMarketplaces` for your own plugins, `allowMemoryEdits = true` if Claude Code should keep its auto-memory. Managed rules under the roots, your own settings elsewhere. |

See `nixos/default.nix` for every option. In a repo, `devenv.nix` sets the
same `harness.allowLocalCommits` and `harness.allowMemoryEdits` as the host
(the hook is built from the repo's values on an unmanaged host), plus
`harness.settings` for allow rules, `harness.extraAllowedDomains`,
`harness.extraDeny` and `harness.allowConnectors` (the claude.ai account's
connectors, off by default: they are MCP servers outside the sandbox).

`allowMemoryEdits` is off by default on purpose: memory under
`~/.claude/projects/<slug>/memory/` is text that every later session on the
machine reads as context, so on a managed host it is a persistence channel for
anything an agent picked up from a repo. With it on, only that directory
opens; the rest of `~/.claude` stays read-only.

Changing the host side is a rebuild: `nh os switch` or `boot` and reboot.
Changing a repo's `devenv.nix` is `direnv reload` in that repo, which
rewrites `.claude/settings.json`; on an unmanaged host that is the only
layer, so that is the whole change. Claude Code reloads settings files
live, but a running session is not the place to confirm a change: restart
it.

The home-manager side (`home/`) is the same on every managed host: direnv
config, tmux rules, `ccmux`, `programs.claude-code`. It never carries deny
rules.

## 5. Verifying after a rebuild or a Claude Code upgrade

Host prerequisites on a host without the home module:
`harness doctor`, one line per item, exit 1 when
something the harness needs is missing. `claude doctor` is the Claude Code
side: install health and settings-file validation, without a session.

From zero on an unmanaged Fedora host, end to end, repeatable. The
bootstrap's `--reset` reverses everything it and the nix packages put on the
host, so the sequence starts from a Fedora with only VS Code, Claude Code
and this checkout on it (a reinstall of Fedora is the same list minus the
first line). `<customer>/<repo>` is a throwaway repo under the code root:
```
harness reset                                 # sudo; asks first; reads the receipt; leaves ~/code/git alone
rm -rf ~/code/git/<customer>/<repo>           # the throwaway repo, so init starts clean
HARNESS_REF=path:$PWD scripts/install.sh      # sudo once: packages, nix.conf, SELinux label, socket; then harness bootstrap --no-root
# new terminal: PATH and NIX_SSL_CERT_FILE come from profile.d and ~/.bashrc.d
harness doctor                                # every line ok
harness init <customer>/<repo>                # files, two allows, 20 settings checks, 154 hook cases
harness check ~/code/git/<customer>/<repo>    # twelve -p sessions
cd ~/code/git/<customer>/<repo> && ccmux            # interactive: trust dialog once, orange window when it waits
```
Log out and in once at the end so GUI-launched VS Code sees the nix profile.
The 2026-10-20 run of this list on the Fedora laptop, with
`raul/harness-test` as the repo, passed; the two host fixes it produced
(SELinux label, CA bundle path) are in the script.

Unit tests, no Claude Code needed, from a checkout of this repo:
```
nix flake check                                     # both managed trees, the repo settings file, ccmux; in the Nix sandbox
nix shell nixpkgs#jq -c tests/hook-test.sh /etc/claude-code/hooks/env-guard.sh   # the installed hook, managed host
nix shell nixpkgs#jq -c tests/hook-test.sh "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' <repo>/.claude/settings.json)"   # the repo's hook
tests/ccmux-test.sh "$(command -v ccmux)"           # inside a repo shell, or after home-manager switch
```
Inside a Claude Code session the sandbox masks shell startup files and
`.gitmodules` in the working directory with device nodes, so Nix cannot
read that directory as a git flake and a bare `nix flake check` there
fails. A session in the test repo can still run all of it against the
harness checkout by path (verified 2026-10-20):
`nix flake check path:<harness checkout>`, `nix build
path:<harness checkout>#project-settings` followed by the tests on the
result, and both unit tests against the repo's own hook and settings file.
Run the flake check from your own terminal before committing anyway; the
`path:` form checks the working tree, not what git tracks.

Live checks, inside a harness repo (the test repo), on any host.
`harness check <repo>` runs them as a script, judged on the
stream-json transcript and on the files afterwards rather than on the
model's prose, and keeps the transcripts for the exact refusal text. By
hand:

```
claude -p 'run: grep -i nonewprivs /proc/self/status'      # NoNewPrivs: 1 => sandboxed
claude -p 'run: git commit -m x'                            # env-guard block
claude -p 'run: cat ~/.azure/msal_token_cache.json'         # blocked
claude -p 'run: echo x > devenv.nix'                        # blocked
claude -p 'edit .envrc and add a comment'                   # blocked
claude -p 'run: claude --dangerously-skip-permissions -p hi' # blocked (nested session)
claude -p 'run: which cargo'                                # the devenv one, not system
claude -p hi --debug-file /tmp/d.txt; grep env-guard /tmp/d.txt   # repo hooks registered (debug goes to a file)
```

Managed hosts only:

```
claude --plugin-dir /tmp/x -p hi                            # rejected at startup
claude -p hi --debug-file /tmp/d.txt; grep -i allowManagedModsOnly /tmp/d.txt   # guard loaded
```

Outside the repo: on an unmanaged host everything your own settings allow;
on a mixed host `git commit` allowed, `sudo` still blocked.

After a Claude Code upgrade also re-read the settings reference for the
keys in `lib/settings.nix`; the file header records the version they were
checked against. Keys that stop existing are silently ignored,
which is the dangerous direction.

## 6. Upgrades and pins

- Claude Code, managed host: from nixpkgs (`programs.claude-code`),
  auto-update disabled, `nix flake update nixpkgs` moves it. Unmanaged
  host: the native install; `claude update` moves it and `autoUpdates`
  stays off in `~/.claude.json` so an upgrade is a decision, followed by
  `harness check`. Minimum 2.1.295 for `onFailure: block`; the
  settings keys were last checked against 2.1.296 (`lib/settings.nix`
  header), the Fedora host runs 2.1.304.
- direnv: `pkgs/direnv.nix` overrides to 2.38.2 while nixpkgs is older. The
  locked nixpkgs (2026-10-14) ships 2.37.1, so the override is in use. At
  the next `nix flake update nixpkgs`, check `nix eval nixpkgs#direnv.version`;
  at 2.38 or newer delete the file and point the one remaining
  unconditional import (`lib/managed-tree.nix` default) at `pkgs.direnv`;
  the NixOS, home and devenv modules and the flake's packages already fall
  back on their own.
- Host tools on an unmanaged host: `harness upgrade`
  after a `nix flake update` or a move of the checkout re-adds direnv,
  devenv and ccmux from the current lock.
- devenv from nixpkgs (2.4.0 at the time of writing). Each repo pins its own
  devenv inputs in `devenv.lock`; `devenv update harness` bumps the harness
  input in one repo.

## 7. Troubleshooting

- **Agent's tools are the system ones, not the project's.** The env hook
  did not run or direnv is not allowed in that directory. Check
  `direnv status` in the repo, and `~/.claude/shell-snapshots/` is not the
  source of PATH any more: the preamble runs `direnv export bash` per
  command.
- **"sandbox unavailable" at start.** `failIfUnavailable` is on, so the
  session refuses to start. bubblewrap needs user namespaces
  (`security.allowUserNamespaces`, asserted by the module) and works nested
  inside `vscode-fhs`. Inside a container it needs `/proc` unmasked.
- **Repo hooks do not fire on an unmanaged host.** Interactive sessions
  hold back every hook from settings files until you accept the workspace
  trust dialog for the folder; `-p` sessions treat it as trusted. Check
  with `claude -p hi --debug-file /tmp/d.txt; grep env-guard /tmp/d.txt` (the
  `Hooks: SessionStart:startup [...env-guard.sh]` line; `--debug` no longer
  writes to stderr). A dangling
  `.claude/settings.json` symlink (store path collected) has the same
  effect; `direnv reload` rewrites it.
- **Plugin or marketplace refused.** `strictKnownMarketplaces` lists only
  the managed directory plus `extraKnownMarketplaces`. Add the source on
  that host, or accept that the plugin does not load there.
- **Plugin hooks silent.** `allowManagedHooksOnly` is on. Expected on a
  managed host.
- **`.claude/settings.json` is a dangling symlink.** The store path was
  garbage collected; enter the shell again (`direnv reload`) and devenv
  rewrites it.
- **Worktree `.envrc` blocked.** It differs from the main checkout's. That
  is the point; make them identical or allow it yourself after reading it.
- **`git push` from a session fails with `Permission denied (publickey)`.**
  Expected in a harness repo: sessions there get no agent socket and no
  `~/.ssh`. You push from your own window (README, "Git over SSH"); sessions
  clone over HTTPS. Outside the roots the agent is available.
- **A push went through without asking.** The key is cached in an agent.
  `ssh-add -l` lists it; `ssh-add -d <key>` removes it, and the host block
  needs `IdentityAgent none` (README, "Git over SSH"). A passphrase asked on
  every push, or a touch for a hardware key, is the design.
- **`nix-daemon.socket` fails with `Failed to create listening socket ...
  Permission denied` on Fedora.** SELinux: `/nix` is `default_t` without a
  policy and systemd may not create a socket there; auditd has the AVC,
  the journal does not. Label the directory the way the Determinate
  installer's `nix.fc` does, which the bootstrap script now does itself:
  `sudo semanage fcontext -a -t var_run_t '/nix/var/nix/daemon-socket(/.*)?'`,
  `sudo restorecon -RF /nix/var/nix/daemon-socket`, then restart the socket.
- **devenv fails with `the SSL certificate is invalid` while fetching an
  input, on Fedora.** Nix-built tools look for the CA bundle at the NixOS and
  Debian path or where `NIX_SSL_CERT_FILE` points, and Fedora 44 keeps it
  only at `/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem`; Fedora's own
  `profile.d/nix-daemon.sh` checks the legacy paths and sets nothing. The
  bootstrap script exports the variable in `~/.bashrc.d`, `environment.d`
  and the mkhl.direnv settings; a terminal opened before it ran lacks it.
- **First `direnv allow` in a new repo ends with `devenv.nix and
  devenv.yaml and devenv.lock require approval`.** Expected: the first
  load created `devenv.lock`. `direnv allow` once more, in the same shell.
- **mkhl.direnv reports that direnv is not found.** VS Code started from the
  menu has the login session's PATH, which on an unmanaged host lacks the
  nix profile until the next login (`~/.config/environment.d`, written by
  the bootstrap script). The script also sets `direnv.path.executable` in
  the VS Code settings, which works at once; check it points at the
  profile's direnv.
- **Hook denies everything, including `ls`.** A regex error makes the ERR
  trap fire, which is the fail-closed design. Run the unit tests; the first
  failing case points at the line.

## 8. Known gaps, by design

- Deny rules and the hook match text. `git -C`, `bash -c`, quoting and
  `env` prefixes are covered by normalisation; a script that opens files
  itself is not. The sandbox and Azure RBAC are the layers for that.
- On a managed host the sandbox is host-wide and cannot be scoped by
  directory. What is hidden from agents in harness repos is hidden in every
  other repo too. On an unmanaged host it comes from the repo file and
  applies inside harness repos only.
- Settings files reload live, so a repo converted while a session is open
  picks up the deny rules; hooks from a file that did not exist at start
  are the uncertain part. Restart the session.
- The hook refuses `.claude/settings.local.json` changes inside a repo,
  which is also where "Yes, and don't ask again" writes. The file is still
  written; the new allow rule applies from the next session. Allow rules
  for a project belong in `devenv.nix` (`harness.settings`).
- Hooks run outside the sandbox with your full permissions. Keep
  `env-guard.sh` small; it is the one script that must be right.
- Without managed settings (unmanaged host) the repo file is the top
  layer. What it cannot do is listed in the README ("What a repo cannot
  enforce on its own"): mod policy, launch flags of the outer `claude`,
  sessions started above the repo, the folder trust dialog, account-synced
  skills and plugins.

Sandbox limits, checked against the sandboxing docs and live on 2026-10-20.
The README's "Lockdown level today" table summarises them; the roadmap's
"sandbox hardening" entry closes them in order:

- Reads are open. A sandboxed command reads the whole machine except the
  `denyRead` paths (`~/.azure`, `~/.gnupg`, `~/.terraform.d`, `~/.netrc`,
  `~/.ssh`). `~/.claude/.credentials.json`, `~/.claude.json`, `~/.aws`,
  `~/.config` and every sibling repo under the code root are readable by
  any command the hook's reader regex does not list, and the Read tool
  reaches them too (`blockReadsOutsideWorkingDirectories` is unset: a
  session in the test repo reads the harness checkout through it, which is
  how this document was checked). The docs allow a read fence from the repo
  file (`denyRead ["~/"]` plus `allowRead` for the repo and the paths devenv
  needs); untested, see the roadmap.
- Glob `denyWrite` entries do nothing on Linux (`mkdir $TMPDIR/x/.claude-plugin`
  succeeds inside the sandbox; they stay for macOS). Since 2026-10-21 the
  repo file repeats the seven protected paths as literal paths under the
  checkout (`config.devenv.root`), which Linux honours; a plugin manifest
  or hook directory elsewhere under `$HOME` is still creatable, and
  `~/.claude` plus Claude Code's own working-directory protections hold.
- Network is prompt-gated unless the user-scope `~/.claude/settings.json`
  sets `sandbox.network.strictAllowlist = true`, which the bootstrap writes
  (user-or-managed scope; a repo cannot). Without it an unlisted host
  prompts in an interactive session and is refused in a `-p` one, which is
  why the live checks look strict either way.
- Every unix socket is reachable (`allowAllUnixSockets`, all-or-none on
  Linux): the D-Bus session bus, the secret service behind it, the display
  server, not only the Nix daemon and go-plugin. One more reason to keep
  `trusted-users` off (the daemon socket would be root-equivalent).
- The environment: since 2026-10-21 the repo file sets
  `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`, which removes credential-shaped
  variables (by name or by value shape; `ANTHROPIC_API_KEY`,
  `AWS_SECRET_ACCESS_KEY`, `*_PASSWORD`, URLs with passwords) from Bash
  commands, hooks and stdio MCP servers, and the sandbox's
  `credentials.envVars` denies the Azure secrets, the SSH agent and the
  GitHub tokens the scrub keeps on purpose. A secret whose name and value
  look like neither is still inherited; name it in `extraDeny`'s sibling,
  `sandbox.credentials.envVars`, through `harness.settings`.
- The hook strips quotes before matching, so a quoted string that mentions
  a config path next to something that looks like a write is refused too:
  `echo "settings -> $(readlink .claude/settings.json)"` (the `->`) and
  `ls ~/.claude/.credentials.json | head` are both denied. Rephrase.

Accepted for now (2026-10-17), after comparing with Hermes Agent, Codex,
destructive_command_guard and codex-protect. Each is a text-matching gap the
other layers are meant to catch; revisit when tightening:

- Shell constructs that compute the command at runtime: `$IFS`, `git\ push`,
  `$(echo git) push`, variable indirection, `base64 -d | sh`, python or node
  spawning git. No regex closes these; the sandbox, the absence of push
  credentials inside it and server-side branch protection are the gate.
- GitHub CLI writes (`gh pr merge`, `gh release create`, `gh repo delete`,
  `gh secret set`, `gh gist create`, `gh api -X DELETE`) and package or
  image publishing (`npm publish`, `cargo publish`, `dotnet nuget push`,
  `docker push`). Same policy as `git push`; not yet encoded.
- Git config keys that run programs: `-c core.hooksPath=`, `core.sshCommand`,
  `credential.helper`, `--config-env`, `git log --output`. The `.git/hooks`
  write block does not cover a hooksPath pointing elsewhere.
- `az storage blob upload` and other az upload or copy verbs: the az regex
  lists mutation verbs, not transfer verbs, and `az` is not in the
  credential-reader list.
- Shell writes to your own config (`echo >> ~/.bashrc`, `authorized_keys`,
  `git config --global`): the Edit tool is blocked, the shell path is left
  to the sandbox write allowlist.
- Outbound transfer (`curl -T`, `scp`, `ngrok`, `ssh -R`): the network
  allowlist is the layer; open by choice on an unmanaged host.
- The nested `claude` launch-flag rule matches the flag word anywhere in
  the command, quotes stripped, so `claude -p "why is --bare refused"` is
  denied too. Rephrase the prompt.
