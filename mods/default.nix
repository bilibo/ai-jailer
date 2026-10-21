# The mods this repository ships, one attribute per mod (docs/sessions.md
# section 5). Each is a plugin directory built by lib/mods.nix.
{ pkgs, lib }:
let
  inherit (import ../lib/mods.nix { inherit pkgs lib; }) mkMod;
in
{
  harness-broker = mkMod {
    name = "harness-broker";
    version = "0.1.0";
    description = "Harness sessions on this machine: a row per session in the store and /fleet to list them (stage A, observe)";
    author = "claude-nix-harness";
    src = ./harness-broker;
  };
}
