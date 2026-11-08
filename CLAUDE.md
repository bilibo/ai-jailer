# ai-jailer

Guard-railed Claude Code for hosts with Nix. This checkout is the
factory: it builds the law (binds everyone on the host), the jail (binds a
worker user) and the cells (a repo's project layer). A session here is the
jailer's: bound by the law alone, no sandbox, and it edits `devenv.nix`,
`.envrc` and `.claude/` like any file. The live hook is the one under
`/etc/claude-code`, not `hooks/`: a working-tree change takes effect only
when the human rebuilds or runs `aj upgrade`. The same goes for
`lib/claude-defaults.md`, the CLAUDE.md every session on the host loads
first; its rules on documentation, comments and delegation apply here.

Never activate a NixOS or home-manager generation, and never change flake
inputs without asking.

## Checks

`nix flake check` (under half a minute), or one check with `nix build
.#checks.x86_64-linux.<name> --no-link`. A pass prints three lines; add
`-L`, or run `nix log`, only after a failure. Nix formatting and lint
commands are in `.claude/rules/nix.md`, loaded when a `.nix` file is open.

A sandboxed worker session cannot run either on the checkout: the sandbox
masks untracked dotfiles, which the `path:` fetcher refuses. Copy the
regular files first:

```sh
git ls-files -co --exclude-standard -z \
  | while IFS= read -r -d '' f; do [ -f "$f" ] && printf '%s\0' "$f"; done \
  | tar --null -T - -cf - | tar -xf - -C <dir>
nix flake check path:<dir>
```

## Which document owns what

- `README.md`: what it is, install, daily use. Short, no history, no
  troubleshooting; also a public face of the author's work. A line goes in
  only when the project's shape changes.
- `docs/runbook.md`: the operator's reference. What to do and the one-line
  why.
- `docs/project-devenv.md`: a project's `devenv.nix`, for someone new to Nix.
- Linear (the connector loads while this checkout's `devenv.nix` sets
  `ai-jail.allowConnectors = true`): tasks, open questions, decisions,
  upstream quirks with their investigation, test journals. A closed
  decision is reopened by a new issue that links the old one (`RAU-nn` in
  a comment points at one). History before 2026-11-01 is at commit
  `30603b1`.

High effort for a subagent is for `hooks/env-guard.sh` and
`lib/settings.nix` only.
