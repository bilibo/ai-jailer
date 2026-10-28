# Nothing here reads `config`, so a nix-darwin module can reuse it unchanged.
{ lib }:
let
  settings = import ./settings.nix { inherit lib; };
in
{
  # { law; jail; }: the two deny lists (lib/deny-rules.nix).
  denyRules = import ./deny-rules.nix { inherit lib; };
  # settings { body = "law"; } is the managed body, { body = "jail"; } a
  # worker's reference body (both built by lib/managed-tree.nix);
  # projectSettings is the repo body, the thin project layer the devenv
  # module writes (`repoRoot` required).
  inherit settings;
  projectSettings = args: settings ({ platform = "linux"; } // args // { body = "repo"; });
  # hooks.nix and managed-tree.nix need pkgs; import them directly where a
  # derivation is wanted.
}
