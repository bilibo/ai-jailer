# Nothing here reads `config`, so a nix-darwin module can reuse it unchanged.
{ lib }:
{
  denyRules = import ./deny-rules.nix { inherit lib; };
  # settings { managed = true; } is the managed body, { managed = false; }
  # the repo body; projectSettings is the latter with its parameters fixed.
  settings = import ./settings.nix { inherit lib; };
  projectSettings = import ./project-settings.nix { inherit lib; };
  # hooks.nix and managed-tree.nix need pkgs; import them directly where a
  # derivation is wanted.
}
