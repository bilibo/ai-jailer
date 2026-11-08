---
paths:
  - "**/*.nix"
---

Before handing over a Nix change: `nixfmt --check $(git ls-files -- '*.nix')`
(`nix shell nixpkgs#nixfmt`), then `nix run nixpkgs#statix -- check <file>`
and `nix run nixpkgs#deadnix -- --fail <file>` on each changed file. Never
`nix fmt` from a session: it finds no tree root and walks the whole visible
filesystem. Never pass `self` into a package.
