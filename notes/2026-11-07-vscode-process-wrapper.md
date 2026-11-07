# VS Code on a worker's repo: the extension's process wrapper, 2026-11-07

Host: Fedora Linux 46 (Rawhide), owner `raul`, worker `w-acme`, repo
`acme/testi`. Claude Code VS Code extension 2.1.319; the repo shell's claude
2.1.309; the owner's host claude 2.1.308 (this checkout's devenv shell).

Question: can the owner open a jailed repo as a VS Code folder and have the
extension's Claude session run as the worker, so the session is jailed like
an `ajmux` one, instead of running as the owner (the law only, no sandbox)?
Remote-SSH to `w-acme@localhost` would do it but was ruled out for WSL.
Running `code` as the worker needs the owner's display (Wayland socket under
`/run/user/1000`, mode 0700) and was not tried.

## What was found

- The extension has a machine-scoped setting
  `claudeCode.claudeProcessWrapper`, "Executable path used to launch the
  Claude process". Read from `extension.js` (2.1.319): when it is set, the
  extension runs `<wrapper> <bundled claude path> <claude args...>` with the
  workspace as cwd, and marks the binary `viaProcessWrapper`. It already
  tolerates an older CLI behind a wrapper for some features (a "too old"
  message for worktree registration). Machine scope means user settings only,
  never `.vscode/settings.json` of the repo, so one wrapper has to decide per
  folder.
- The bundled binary lives under `~/.vscode/extensions/anthropic.claude-code-*`
  in the owner's 0700 home: a worker cannot run it. The worker's claude has to
  be the repo shell's (`ai-jail.claudeCode.enable`), as with `ajmux`.
- The inner leg works: as the worker,
  `sudo -n -u w-acme -i env X=1 direnv exec /home/w-acme/code/git/acme/testi claude --version`
  prints 2.1.309. The NOPASSWD sudo rule covers it.
- `mkhl.direnv` makes the VS Code window load the repo's `.envrc`, so the
  window and its terminals get the devenv shell, but as the owner. The
  environment is the jail's, the user is not. Only the wrapper changes the
  user.
- Editing the worker's files in the editor is a separate problem: the owner
  is in group `w-acme` (home 0750) and can read, not write. Default ACLs on
  the repo (`setfacl -R -m u:raul:rwX -m d:u:raul:rwX <repo>`) plus
  `git config --global --add safe.directory <repo>` are the candidate fix,
  not tried.

## What was done, and reverted

A test wrapper `~/.local/bin/ajcode` was written and the setting
`claudeCode.claudeProcessWrapper` was added to the owner's
`~/.config/Code/User/settings.json` pointing at it. Both were removed the
same evening before any VS Code test ran: the session's group membership
predated bootstrap, so the owner side (opening the worker's folder) could not
be exercised; only the worker-side command above was. Nothing of this is on
the host now.

The wrapper, for the record:

```bash
#!/usr/bin/env bash
# ajcode: claudeCode.claudeProcessWrapper. Called as
# ajcode <bundled claude> <claude args...>, cwd = the workspace.
set -euo pipefail
bundled=$1; shift
repo=$PWD
worker=$(stat -c %U "$repo")
if [ "$worker" != "$(id -un)" ] && id -nG "$worker" 2>/dev/null | tr ' ' '\n' | grep -qx agents; then
  # sudo -i starts a clean login environment; forward what the extension set
  # for its process via env(1).
  fwd=()
  while IFS= read -r -d '' kv; do
    case "$kv" in CLAUDE_*=*|ANTHROPIC_*=*|VSCODE_*=*|TERM_PROGRAM*=*) fwd+=("$kv") ;; esac
  done < <(env -0)
  exec sudo -n -u "$worker" -i env "${fwd[@]}" direnv exec "$repo" claude "$@"
fi
exec "$bundled" "$@"
```

Open points before it can be more than a draft: which environment variables
the extension needs forwarded (the filter above is a guess); whether the
extension's stdio protocol survives `sudo -i`; the version gap between the
extension and the repo shell's CLI; whether the forwarded `CLAUDE_*`
variables ever point into the owner's home, unreadable to the worker.

## If it works

The wrapper becomes a package next to `ajmux`; `aj bootstrap` writes the
setting into the VS Code user settings the way it writes
`direnv.path.executable`; `aj init` applies the ACLs. It would replace the
Remote-SSH idea and also work under WSL, where the wrapper runs inside WSL.

Test plan, from a fresh login (group `w-acme` present): install
`mkhl.direnv` from the extensions view (the CLI install dumps core on this
Rawhide, see the bootstrap change of 2026-11-07), put the wrapper and the
setting back, open `/home/w-acme/code/git/acme/testi` as a folder, start a
session from the extension, ask it for `id -un` (expect `w-acme`) and a `git
commit` (expect a refusal). Failures show in the extension's Claude Code
output channel.
