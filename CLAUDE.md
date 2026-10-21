# claude-nix-harness

Guard-railed Claude Code for hosts with Nix. This checkout is itself a
harness repo (the root `devenv.yaml` imports `./devenv`), so a session here
runs under the repo file: the hook refuses edits to `devenv.nix`,
`devenv.yaml`, `.envrc` and `.claude/`; propose those as diffs. Agents stage
and diff; the human commits and pushes.

## Which document owns what

- `README.md`: current state, the layers, the host and lockdown tables.
- `docs/roadmap.md`: what is next, in order; its "Done" list is what exists.
- `docs/changelog.md`: dated history, newest first, with what was learned.
- `docs/handoff-tiers.md`: the tier, read-fence and customer-module phases,
  and the standing rule: never activate a NixOS or home-manager generation,
  never change flake inputs without asking.
- `docs/sessions.md`: how sessions coordinate (tiers, proposals, broker mod).
- `docs/runbook.md`: what the operator types; written for the human.

A closed decision is reopened only by a new dated roadmap or changelog
entry, never by editing the old one. Dates are absolute, never relative.

## Checks

A bare `nix flake check` fails inside a session (the sandbox masks
`.gitmodules` as a device node): run it on a `git archive` copy, or as
`nix flake check path:<checkout>` from the test repo. Before handing over
Nix changes: `nix fmt`, `statix`, `deadnix`; never pass `self` into a
package.
