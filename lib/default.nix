# Nothing here reads `config`, so a nix-darwin module can reuse it unchanged.
{ lib }:
let
  settings = import ./settings.nix { inherit lib; };
in
{
  denyRules = import ./deny-rules.nix { inherit lib; };
  # The law and jail bodies are built by lib/managed-tree.nix; projectSettings
  # is the repo body the devenv module writes (`repoRoot` required).
  inherit settings;
  projectSettings = args: settings ({ platform = "linux"; } // args // { body = "repo"; });
  # hooks.nix and managed-tree.nix need pkgs; import them directly where a
  # derivation is wanted.
}
