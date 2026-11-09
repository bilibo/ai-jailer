# One store path, linked at /etc/claude-code on the host: the law
# (managed-settings.json, read by Claude Code for every user), the jail
# (jail-settings.json, the reference copy of a worker's rules that `aj
# bootstrap` writes into each worker's user settings and the hook checks
# them against), the hooks the law calls, and CLAUDE.md: the defaults
# Claude Code loads first into every session on the host (claude-defaults.md
# here, then the host's extraInstructions). No plugin or marketplace
# directory: ai-jailer ships no mods, and the law refuses every mod
# (lib/settings.nix).
{
  pkgs,
  lib,
  platform ? "linux",
  allowLocalCommits ? false,
  allowMemoryEdits ? false,
  allowConnectors ? false,
  allowCloudCli ? false,
  extraDeny ? [ ],
  extraAllowedDomains ? [ ],
  allowManagedHooksOnly ? true,
  extraKnownMarketplaces ? [ ],
  # Appended to the host-wide CLAUDE.md, for what one host's projects share.
  extraInstructions ? "",
  direnvPackage ? pkgs.direnv,
  # The JSON refers to its own hooks by this stable path, not by store path.
  managedDir ? "/etc/claude-code",
}:
let
  jailerLib = import ./default.nix { inherit lib; };

  hooks = import ./hooks.nix {
    inherit
      pkgs
      lib
      direnvPackage
      allowLocalCommits
      allowMemoryEdits
      ;
  };

  law = jailerLib.settings {
    body = "law";
    inherit
      platform
      allowLocalCommits
      allowMemoryEdits
      allowManagedHooksOnly
      extraKnownMarketplaces
      ;
    hookDir = "${managedDir}/hooks";
  };
  # The host's extra deny rules and domains are the workers': the law's
  # content is fixed.
  jail = jailerLib.settings {
    body = "jail";
    inherit
      platform
      allowLocalCommits
      allowMemoryEdits
      allowConnectors
      allowCloudCli
      extraDeny
      extraAllowedDomains
      ;
    syncClaudeAi = false;
  };
  lawJson = (pkgs.formats.json { }).generate "managed-settings.json" law;
  jailJson = (pkgs.formats.json { }).generate "jail-settings.json" jail;
  instructions = pkgs.writeText "CLAUDE.md" (
    builtins.readFile ./claude-defaults.md
    + lib.optionalString (extraInstructions != "") "\n${extraInstructions}\n"
  );
in
pkgs.runCommand "ai-jailer-managed" { } ''
  mkdir -p $out
  cp ${lawJson} $out/managed-settings.json
  cp ${jailJson} $out/jail-settings.json
  cp ${instructions} $out/CLAUDE.md
  cp -r ${hooks} $out/hooks
''
