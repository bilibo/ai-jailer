# ai-jailer

Guard-railed Claude Code for hosts with Nix. This checkout is the
factory: it builds the law (what binds everyone on the host), the jail
(what binds a worker user) and the cells (a repo's project layer), and a
session here is the jailer's (roadmap item 14, 2026-10-28). Once the host
is bootstrapped a session here is bound by the law alone: no credential
reads, no `git commit`, no `git push`; no sandbox, and the hook's other rules are the
workers'. It edits `devenv.nix`, `devenv/devenv.nix`, `.envrc` and
`.claude/` here like any file. The root `devenv.yaml` imports `./devenv`
from the working tree. That is fine because the live hook is the one
under `/etc/claude-code`, not the tree's `hooks/`: a working-tree edit
takes effect only when the human rebuilds or runs `aj upgrade`. Agents
stage and diff; the human commits and pushes. A worker's handoff goes to
`proposals/<date>-<topic>.patch` at its checkout root (gitignored),
applied with `git apply`; never only the session scratchpad, which the
human cannot reach.

## Which document owns what

- `README.md`: current state, the layers, the host and lockdown tables;
  what exists.
- `docs/roadmap.md`: what is next, in order.
- `docs/changelog.md`: dated history, newest first, with what was learned.
- `docs/verified.md`: one row per live check (date, claim, how, result);
  the evidence a README or runbook claim points at. Rows come from runs
  on a host, never from reading the code.
- `docs/sessions.md`: how sessions coordinate (tiers, proposals).
- `docs/runbook.md`: what the operator types; written for the human.
- `docs/project-devenv.md`: a project's `devenv.nix`, for a human who
  does not know Nix; `aj init`'s template links it.
- `docs/suggestion.md`: ideas with a shape but no commitment; the
  roadmap's "Ideas, not planned" points here.

A closed decision is reopened only by a new dated roadmap or changelog
entry, never by editing the old one. Dates are absolute, never relative.

Never activate a NixOS or home-manager generation, and never change flake
inputs without asking.

## Checks

An unsandboxed session (the jailer's, here) runs `nix flake check` and
`nix build .#checks.x86_64-linux.<name> --no-link` straight on the
checkout (the full check 25 s, one check 4 s, 2026-10-29). A passing
run prints three lines; add `-L`, or run `nix log`, only after a
failure.

A sandboxed worker session cannot: a bare `nix flake check` fails there,
and so does `path:` on the checkout, because the sandbox masks the
checkout's untracked dotfiles (`.bashrc`, `.gitmodules`, `.vscode`, ...)
as device nodes or empty files, which the `path:` fetcher refuses. The
fallback is a copy of the regular files only:

```sh
git ls-files -co --exclude-standard -z \
  | while IFS= read -r -d '' f; do [ -f "$f" ] && printf '%s\0' "$f"; done \
  | tar --null -T - -cf - | tar -xf - -C <dir>
nix flake check path:<dir>
nix build path:<dir>#checks.x86_64-linux.<name> --no-link
```

Before handing over Nix changes: format, `statix`, `deadnix`; never pass
`self` into a package. From a session `nix fmt` finds no tree root in the
copy and walks the whole visible filesystem (six minutes, nothing
formatted, 2026-10-24), so run the tools on the files: `nixfmt --check
$(git ls-files -- '*.nix')` (`nix shell nixpkgs#nixfmt`), `nix run
nixpkgs#statix -- check <file>`, `nix run nixpkgs#deadnix -- --fail
<file>`.
