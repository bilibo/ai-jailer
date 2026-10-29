# Verified

What has been tested live, when, how, and what came out. One row per
claim. The roadmap decides and the changelog narrates; this table is the
evidence, so a claim in the README or the runbook can point at a row.
Add a row when a check runs for real on a host; never from reading the
code. A row that stops being true gets a new dated row below it, the old
one stays.

Host for every row unless said otherwise: nixos-wsl, owner `nixos`,
workers `w-acme` (uid 1001) and `w-globex`, jail `acme/infra`.

| Date | Claim | How | Result |
| --- | --- | --- | --- |
| 2026-10-29 | A worker session is sandboxed even in a bare directory with no repo file (V1) | as `w-acme`, `mktemp -d`, `claude -p` running `grep -i nonewprivs /proc/self/status` | `NoNewPrivs: 1`; the sandbox comes from the jail in the user scope |
| 2026-10-29 | A cell's `ai-jail.extraAllowedDomains` reaches the sandbox proxy's allowlist (V2) | `extraAllowedDomains = [ "dev.azure.com" ]` in `acme/infra`'s `devenv.nix`, `direnv allow`, `claude -p` running `curl -sI https://dev.azure.com` and the same for `example.org` | `dev.azure.com` tunnelled (`200 Connection Established`); `example.org` `deny network-outbound example.org:443 (user denied)`, no prompt |
| 2026-10-29 | `extraAllowedDomains = [ "*" ]` opens the network (V3) | same, with `"*"`, `curl -sI https://example.org` | tunnelled, no prompt |
| 2026-10-29 | The owner watches a worker by becoming it; nothing is shared (V4) | `ajmux acme/infra` in one tab, `sudo -u w-acme -i tmux attach -t acme-infra` in another as `nixos`; `ls -la /tmp/tmux-1001/`, `tmux -S /tmp/tmux-1001/default ls` | both tabs show the same pane; the socket dir is 0700 `w-acme`, both direct commands denied |
| 2026-10-29 | `ajmux`'s `XDG_RUNTIME_DIR` export reaches the pane; linger keeps the directory (V5) | `/proc/<pane_pid>/environ`, `ls -ld /run/user/1001` | `XDG_RUNTIME_DIR=/run/user/1001`, `TMUX=` set, no `DIRENV_*`; directory present |
| 2026-10-29 | A worker cannot list the owner's or another worker's home; the owner reads the worker's repo (V7) | `sudo -u w-acme -i sh -c 'ls /home/nixos; ls /home/w-globex'`; `ls /home/w-acme/code/git/acme/infra` as `nixos` | both denied; the owner lists the repo |
| 2026-10-29 | `aj check` passes as a worker (V8, V13) | `aj check` as `w-acme` in `acme/infra`, logged in with `claude auth login` | `17 passed, 0 failed, 1 skipped` (tmux-display, outside tmux) |
| 2026-10-29 | `syncClaudeAiSkills = false` is honoured, as far as the log shows (V9) | `claude -p "say ok" --debug-file` as `w-acme`; `ls ~/.claude/skills` | skills loaded from the managed, user and project paths only, no sync line, no skills directory |
| 2026-10-29 | A committed project file that turns the sandbox off locks the worker out (V12) | a directory under the worker's home with only `.claude/settings.json` saying `"enabled": false`, `claude -p "run pwd"` | `env-guard: worker without a sandbox: ... resolve to (false false true), not (true false true)`, exit 2, the model stopped |
| 2026-10-29 | A worker whose user settings lost a jail rule has every tool refused; `aj bootstrap` repairs it (V14) | as `w-acme`: `jq "del(.permissions.deny[0])"` into `~/.claude/settings.json`, `claude -p "run pwd"`; then `aj bootstrap --no-root --yes` | `env-guard: worker without a jail: ... differs from ... at permissions`, exit 2; `aj doctor` MISSING with the same words; after bootstrap hook exit 0, doctor 0 missing |
| 2026-10-29 | A jailer session in the checkout works unsandboxed and is still bound by the law (V15) | from a session: `nix flake check`, `git add`, `sudo -v`; `git commit`, `git push`, `cat ~/.ssh/id_ed25519` | the first three ran; the three refusals each came back from the hook |
| 2026-10-29 | A mode switch in the TUI writes `permissions.defaultMode` into the worker's user file | `ajmux acme/infra`; the file's mtime and a key diff against `jail-settings.json` one minute later | `defaultMode: "auto"`, `theme`, `tui` written; with the jail pinning `defaultMode` the hook refused every tool (V14's message). Fixed the same day: the jail no longer carries the key and the comparison leaves it out |
| 2026-10-29 | Bypass permissions mode is off for a worker | as `w-acme`: `claude --dangerously-skip-permissions -p ...` and `claude --permission-mode bypassPermissions -p ...` with `--debug-file`, the command `grep -i nonewprivs /proc/self/status` | no message in the `-p` output; the debug log says `[WARN] bypassPermissions mode is disabled by settings`; the command ran sandboxed (`NoNewPrivs: 1`) |
| 2026-10-29 | A `permissions.deny Read(<glob>)` rule is merged into the sandbox's read fence and expanded through symlinks | `Read(**/.devenv/**)` added to the jail, any sandboxed command | every command died with `bwrap: execvp /bin/bash: No such file` (the glob reached the bash package through `.devenv/bash-bash`); reverted |
| 2026-10-29 | The host matches its flake and the ai-jailer lock after `nix flake update ai-jailer && nh os switch` | `sh /etc/nixos/scripts/wsl/verify.sh` | `37 ok, 0 failed` |
| 2026-10-29 | The managed hook refuses a jailer's Bash call whose text names a credential file, heredocs included | a session writing a script that mentioned a state-file name through a heredoc | `env-guard: credential file access blocked`; the edit went into a scratchpad script run by path |
| 2026-10-29 | A worker's first login is `claude auth login`, one prompt | as `w-acme` | `claude /login` on a first launch prompts twice (onboarding, then the command); `claude auth login` once |
