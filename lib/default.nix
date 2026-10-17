# Pure helpers shared by the NixOS module, the home-manager module and the
# devenv module. Nothing here reads `config`, so the same functions can
# later back a nix-darwin module without change.
{ lib }:
{
  denyRules = import ./deny-rules.nix { inherit lib; };
  managedSettings = import ./managed-settings.nix { inherit lib; };
  projectSettings = import ./project-settings.nix { inherit lib; };
  # managed-tree.nix needs pkgs; import it directly where a derivation is wanted.
}
