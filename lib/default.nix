# Nothing here reads `config`, so a nix-darwin module can reuse it unchanged.
{ lib }:
let
  settings = import ./settings.nix { inherit lib; };
in
{
  denyRules = import ./deny-rules.nix { inherit lib; };
  # settings { managed = true; } is the managed body with every rule;
  # projectSettings is the repo body, the thin project layer the devenv
  # module writes (`repoRoot` required).
  inherit settings;
  projectSettings = args: settings ({ platform = "linux"; } // args // { managed = false; });
  # hooks.nix and managed-tree.nix need pkgs; import them directly where a
  # derivation is wanted.
}
