# One store path, linked at /etc/claude-code on the host: the law
# (managed-settings.json, read by Claude Code for every user), the jail
# (jail-settings.json, the reference copy of a worker's rules that `aj
# bootstrap` writes into each worker's user settings and the hook checks
# them against) and the hooks the law calls. No plugin or marketplace
# directory: the ai-jailer ships no mods (2026-10-24, docs/sessions.md
# section 5), and the law refuses every mod (lib/settings.nix).
{
  pkgs,
  lib,
  platform ? "linux",
  allowLocalCommits ? false,
  allowMemoryEdits ? false,
  allowConnectors ? false,
  extraDeny ? [ ],
  extraAllowedDomains ? [ ],
  allowManagedHooksOnly ? true,
  extraKnownMarketplaces ? [ ],
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
  # The host's extra deny rules and domains are the workers' (roadmap item
  # 14): the law's content is fixed, one dated entry per rule.
  jail = jailerLib.settings {
    body = "jail";
    inherit
      platform
      allowLocalCommits
      allowMemoryEdits
      allowConnectors
      extraDeny
      extraAllowedDomains
      ;
    syncClaudeAi = false;
  };
  lawJson = (pkgs.formats.json { }).generate "managed-settings.json" law;
  jailJson = (pkgs.formats.json { }).generate "jail-settings.json" jail;
in
pkgs.runCommand "ai-jailer-managed" { } ''
  mkdir -p $out
  cp ${lawJson} $out/managed-settings.json
  cp ${jailJson} $out/jail-settings.json
  cp -r ${hooks} $out/hooks
''
