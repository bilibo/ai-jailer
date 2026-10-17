# Nothing here reads `config`, so a nix-darwin module can reuse it unchanged.
{ lib }:
{
  denyRules = import ./deny-rules.nix { inherit lib; };
  managedSettings = import ./managed-settings.nix { inherit lib; };
  projectSettings = import ./project-settings.nix { inherit lib; };
  # managed-tree.nix needs pkgs; import it directly where a derivation is wanted.
}
