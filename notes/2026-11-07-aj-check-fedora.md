# ai-jailer worker shape on Fedora: first live run, 2026-11-07

Host: Fedora Linux 46 (Rawhide), SELinux Enforcing, Nix from Fedora's
packages, Claude Code 2.1.309 from the repo's devenv shell
(`ai-jail.claudeCode.enable`), bubblewrap 0.12, direnv 2.38.2, devenv 2.4.0.
Owner `raul`, worker `w-acme`, repo `acme/testi`. ai-jailer at
`path:/home/raul/code/ai-jailer`, revision `dirty`.

Result: `aj doctor` clean on both sides; `ajmux acme/testi -p ...` handed
over and answered; `aj check` 19 passed, 1 failed. Transcripts in
`/tmp/aj-check.E2sJCU` (the full run), `/tmp/aj-check.G46vmN` and
`/tmp/aj-check.WKLd4B` (two aborted starts at 18:37).

Each finding below has evidence, a reproduction and a proposed fix so it
can be filed as is.

---

## 1. The sandbox leaves zero-byte files in the repo for denied paths that do not exist

**Severity: high.** Breaks `git config` for the human, pollutes `git status`,
and makes the `repo-write` check fail on every run after the first.

### Evidence

After the first bubblewrapped Bash command in `acme/testi`, 24 entries
appeared on the host, all created between 18:37:46.823 and 18:37:46.856,
all `-r--r--r--`, all 0 bytes, all regular files (also the ones whose names
are directories elsewhere):

```
# repo root
.bash_profile  .bashrc  .profile  .zprofile  .zshrc  .ripgreprc
.gitconfig  .gitmodules  .claude-plugin  .mcp.json  .idea  .vscode
# .git/
config.lock
# .claude/
settings.local.json  launch.json  loop.md  scheduled_tasks.json
agents  commands  hooks  skills  output-styles  routines  workflows
```

Found with `find . -maxdepth 2 -size 0 -perm 444`. `git status` lists the
root ones as untracked (`.bash_profile`, `.bashrc`, `.claude-plugin`,
`.gitconfig`, `.gitmodules`, `.idea`, `.mcp.json`, `.profile`,
`.ripgreprc`, `.vscode`, `.zprofile`, `.zshrc`) plus `.claude/`.

The creator: session `3af267ea` in `/tmp/aj-check.WKLd4B`, the `sandbox`
case of the second aborted run, first message 18:37:44.7, command
`grep -i nonewprivs /proc/self/status`. Nothing else ran in the repo in that
window. The earlier `ajmux -p` session (18:24, `f37eb386`) made two Bash
calls that never reached bubblewrap (hook-refused), and left nothing.

The same thing is visible in the worker's home, which was the cwd of the
first ever session as `w-acme` (16:32:45): from inside a sandbox,
`~/.gitmodules` and `~/.idea` show as `/dev/null` character devices, the
mask the sandbox puts over a denied path. On the host they are regular
empty files.

None of these names are in the jail. `/etc/claude-code/jail-settings.json`
`denyWrite` lists `~/.claude`, `~/.config`, `~/.azure`, `~/.ssh`,
`**/.git/hooks`, `**/.git/config`, `**/devenv.local.*`,
`**/.claude/settings*.json`, `**/.claude/hooks`, `**/.claude/skills`,
`**/.claude-plugin`. `.bashrc`, `.bash_profile`, `.gitconfig`,
`.gitmodules`, `.idea` and `.git/config.lock` come from Claude Code's own
built-in protected-file set, resolved against the session cwd.

### Mechanism

bubblewrap cannot bind over a path that does not exist, so a mount point is
created first. When the parent directory is a read-write bind of a host
directory (the repo, the home), that mount point is created on the host and
is never removed. The comment in `aj-check` at the `repo-write` case
("masked as a device node whether or not it exists ... 'File exists'",
2026-10-22) describes the view from inside the sandbox and did not know
about the residue on the host.

### Impact

- `.git/config.lock` is a real file on the host now. Every `git config`
  write in that repo fails for everyone, the human included, with
  `error: could not lock config file .git/config: File exists`. Removing it
  fixes git until the next sandboxed command recreates it.
- The `git-hookspath` check passes on `could not lock config file`, so it
  is green for a reason that also blocks the owner.
- The `repo-write` check fails on every run after the first
  (`.claude-plugin exists on the host; the case needs a repo without one`),
  which is the one failure in this run.
- A dozen untracked files in every jailed repo; of the `aj init`
  `.gitignore` lines only `.claude/settings.local.json` covers one of them.
- `.vscode`, `.idea`, `.claude/hooks`, `.claude/skills`, `.claude/agents`,
  `.claude/commands` exist as read-only regular files, so the human cannot
  create those directories in the repo any more (VS Code and JetBrains
  project settings, legitimate project hooks and skills) until the file is
  removed, and it comes back at the next sandboxed command.
- `.mcp.json` and `.claude/settings.local.json` are blank files. Claude Code
  2.1.309 tolerates both (`MCP config is blank, read as no servers` in the
  debug log; the settings file is watched without error), so no parse
  failure today, but any tool that treats their presence as meaningful
  sees a config file that is not one.

### Reproduction

1. Fresh clone of any repo under the worker's code root, `direnv allow`.
2. One session with one Bash command that reaches bubblewrap, e.g.
   `claude -p 'run: grep -i nonewprivs /proc/self/status' --max-turns 1`.
3. `ls -la .claude-plugin .gitmodules .git/config.lock` on the host.
4. `git config test.x y` on the host: `could not lock config file`.

### To verify from the owner's terminal

```
ls -la ~w-acme/code/git/acme/testi/.claude-plugin ~w-acme/code/git/acme/testi/.git/config.lock
ls -la ~w-acme/.gitmodules ~w-acme/.idea
```

### Proposed fixes

- **Upstream (Claude Code):** create mount points for non-existent
  `denyWrite` targets on a tmpfs layer, or remove them after the command.
  Report with the file list above and the 2.1.309 version.
- **ai-jailer, `aj check`:** detect the residue before the `repo-write`
  case and report it as its own finding (`warn`, with the explanation and
  the `rm` list) instead of `FAIL repo-write` with a message that blames the
  repo. Include `.git/config.lock` in the check.
- **ai-jailer, `aj init`:** gitignore the root residue as a stopgap:
  `.bash_profile`, `.bashrc`, `.profile`, `.zprofile`, `.zshrc`,
  `.ripgreprc`, `.gitconfig`, `.gitmodules`, `.claude-plugin`, `.mcp.json`,
  `.idea`, `.vscode`, and the `.claude/` entries. `.git/config.lock` cannot
  be gitignored and the directory-blocking files cannot be ignored away;
  both stay an upstream problem.
- **Runbook, section 2:** document the residue as expected behaviour of the
  current Claude Code and what the owner removes when `git config` fails.

---

## 2. Docs: `~` after `sudo -u w-acme -i` expands in the owner's shell

**Severity: medium.** Every copy-pasted `aj check` example in the docs
points at the owner's home.

### Evidence

```
raul$ sudo -u w-acme -i aj check ~/code/git/acme/testi
aj check: no such directory: /home/raul/code/git/acme/testi
```

Bash expands `~` to `/home/raul` before sudo runs. Locations:

- `README.md:248`
- `docs/runbook.md:251`
- `docs/runbook.md:293`

The review step already uses the right form:
`git -C ~w-acme/code/git/acme/infra diff --cached`.

### Proposed fix

Replace `~/code/git/acme/infra` with `~w-acme/code/git/acme/infra` in every
example that follows `sudo -u w-acme -i`, and say once in the runbook why.

---

## 3. `aj doctor` as a worker demands VS Code extensions and exits 1

**Severity: low.** A correctly set up worker reports `1 missing`.

### Evidence

```
w-acme$ aj doctor
...
warn  VS Code extension anthropic.claude-code not installed
MISSING VS Code extension mkhl.direnv (code --install-extension mkhl.direnv)
...
aj doctor: 1 missing, 2 warnings
```

`aj-bootstrap:1174-1182` runs the VS Code checks for the caller regardless
of standing. The worker never opens VS Code: the owner's tabs attach to the
worker's tmux, and the worker gets `claude` from the repo shell. The checks
belong to the owner only. Anyone scripting `sudo -u w-acme -i aj doctor`
gets a false failure.

### Proposed fix

Gate both checks on the owner standing, or print them as `info` for a
worker.

---

## 4. The worker shape runs live on Fedora: update the host table

**Severity: info.** Positive result for the runbook.

The runbook's host table (section 4) marks Fedora in the worker shape as
"stubbed-host tests only, not yet run live". This run covers it:

- host root steps, worker user, linger, sudoers: `aj doctor` ok on both sides
- `ajmux acme/testi -p ...` handed over via `sudo -u w-acme -i ajmux`, took
  `claude` from the repo's devenv shell (`direnv exec`), and answered
- `aj check`: 19 of 20, the one failure being finding 1
- `tmux-notify` coloured the window (`colour214`) on `Stop`
- `home-fence`: `/home/raul` closed to the worker
- SELinux Enforcing: no denials hit anything in the run

Not covered yet: `--worktree` sessions, the owner reviewing a staged diff
through the group, and `aj reset`.

---

## 5. Minor observations

- **Aborted `aj check` runs keep their transcript directory.** Two aborted
  starts left `/tmp/aj-check.G46vmN` and `/tmp/aj-check.WKLd4B`. Keeping
  transcripts of a finished run is by design; an aborted run could remove
  its own, or the header could mention `rm -r /tmp/aj-check.*`.
- **The hook matches command text, as documented.** In the owner-side
  Claude session used for this investigation, read-only `grep` commands
  whose pattern contained `chmod 444`, `install -m` or `sudo -u` were refused
  (`shell write to config file blocked`, `privilege escalation blocked`).
  Expected per the README; worth one line in runbook section 2 so an agent
  reading transcripts knows to rephrase, not retry.
- **`git-hookspath` pass criterion.** `could not lock config file` is
  accepted as a pass. After finding 1 that message no longer proves the
  sandbox denied the write; it also appears because of the host-side lock
  residue. Consider matching on `Read-only file system` or `not permitted`
  for the `.git/config` path, or checking that `.git/config.lock` did not
  exist before the case.

---

## Cleanup after this run (as `w-acme`, outside any session)

```
cd ~/code/git/acme/testi
find . -maxdepth 2 -type f -size 0 -perm 444 -not -path './.devenv/*' -not -path './.direnv/*'   # review the list first
find . -maxdepth 2 -type f -size 0 -perm 444 -not -path './.devenv/*' -not -path './.direnv/*' -delete
find ~ -maxdepth 1 -type f -size 0 -perm 444                                                        # the home has the same residue (.gitmodules, .idea, ...)
```

The `-type f -size 0 -perm 444` triple matches only the residue; nothing
that `aj init` or devenv writes has that shape. They return at the next
sandboxed command until the upstream fix lands.
