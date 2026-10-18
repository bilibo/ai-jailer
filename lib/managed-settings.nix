# Superseded by settings.nix (one body for the managed and the repo copy).
# Kept one release so an external `lib.managedSettings` import still
# evaluates; delete it with `git rm lib/managed-settings.nix`.
{ lib }:
args: import ./settings.nix { inherit lib; } ({ managed = true; } // args)
