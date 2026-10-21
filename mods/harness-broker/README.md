# harness-broker

The broker mod of docs/sessions.md section 5. This directory holds the hooks
module (`hooks/register.ts`), its types and its tests; the manifest is
written by `lib/mods.nix` from `mods/default.nix`, so there is no
`.claude-plugin` directory here (the deny rules keep an agent out of one).

What is in: the first slice of stage A. `session.start` writes the session's
row to `$.store`, shows the tier in the status line, registers `/fleet`;
`session.end` removes the row; `/fleet` prints one line per recorded
session. Nothing changes behaviour.

The loop, from the checkout, in a terminal (an agent's session cannot run
`claude plugin`):

```
nix build .#harness-broker
claude plugin validate --strict result
claude plugin test result
claude --plugin-dir result          # a session with the mod loaded
```

`tests/mod-validate-test.sh <marketplace dir>` runs the first two over every
mod in the built marketplace (`nix build .#managed-mods`, then
`result/plugins`); `nix flake check` carries it when the evaluator allows
unfree packages (claude-code in nixpkgs is unfree).
