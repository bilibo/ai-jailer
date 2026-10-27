# ai-jailer

Guard-railed Claude Code for hosts with Nix. This checkout is the ai-jailer
repo, and a session here runs under the host's managed settings like a
session in any repo, sandbox on: the hook refuses edits to `devenv.nix`,
`devenv.yaml`, `devenv/devenv.nix`, `.envrc` and `.claude/` here as
everywhere; propose those as diffs. The root `devenv.yaml` imports
`./devenv` from the working tree. That is fine because the live hook is
the one under `/etc/claude-code`, not the tree's `hooks/`: a working-tree
edit takes effect only when the human rebuilds or runs `aj upgrade`.
Agents stage and diff; the human commits and pushes.

## Which document owns what

- `README.md`: current state, the layers, the host and lockdown tables;
  what exists.
- `docs/roadmap.md`: what is next, in order.
- `docs/changelog.md`: dated history, newest first, with what was learned.
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

A bare `nix flake check` fails inside a sandboxed session, and so does
`path:` on the checkout: the sandbox masks the checkout's untracked dotfiles
(`.bashrc`, `.gitmodules`, `.vscode`, ...) as device nodes or empty files,
which the `path:` fetcher refuses. Run it on a copy of the regular files
only:

```
git ls-files -co --exclude-standard -z \
  | while IFS= read -r -d '' f; do [ -f "$f" ] && printf '%s\0' "$f"; done \
  | tar --null -T - -cf - | tar -xf - -C <dir>
nix flake check path:<dir>
```

One check at a time: `nix build path:<dir>#checks.x86_64-linux.<name>
--no-link -L`. Before handing over Nix changes: format, `statix`,
`deadnix`; never pass `self` into a package. From a session `nix fmt`
finds no tree root in the copy and walks the whole visible filesystem
(six minutes, nothing formatted, 2026-10-24), so run the tools on the
files: `nixfmt --check $(git ls-files -- '*.nix')` (`nix shell
nixpkgs#nixfmt`), `nix run nixpkgs#statix -- check <file>`, `nix run
nixpkgs#deadnix -- --fail <file>`.
