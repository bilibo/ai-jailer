# One store path, linked at /etc/claude-code on the host: the managed
# settings and the hooks they call. No plugin or marketplace directory: the
# ai-jailer ships no mods (2026-10-24, docs/sessions.md section 5), and the
# managed settings refuse every mod (lib/settings.nix).
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

  settings = jailerLib.settings {
    managed = true;
    inherit
      platform
      allowLocalCommits
      allowMemoryEdits
      allowConnectors
      extraDeny
      extraAllowedDomains
      allowManagedHooksOnly
      extraKnownMarketplaces
      ;
    hookDir = "${managedDir}/hooks";
    syncClaudeAi = false;
  };
  settingsJson = (pkgs.formats.json { }).generate "managed-settings.json" settings;
in
pkgs.runCommand "ai-jailer-managed" { } ''
  mkdir -p $out
  cp ${settingsJson} $out/managed-settings.json
  cp -r ${hooks} $out/hooks
''
