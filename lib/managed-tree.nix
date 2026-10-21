# One store path, linked at /etc/claude-code on the host.
{
  pkgs,
  lib,
  platform ? "linux",
  allowLocalCommits ? false,
  allowMemoryEdits ? false,
  allowConnectors ? false,
  enforcementRoots ? [ ],
  extraDeny ? [ ],
  extraAllowedDomains ? [ ],
  allowManagedHooksOnly ? true,
  strictAllowlist ? true,
  extraKnownMarketplaces ? [ ],
  # Mods built by lib/mods.nix, shipped at `$out/plugins/<name>` and enabled
  # from the managed settings. Empty: an empty, unregistered marketplace.
  mods ? [ ],
  direnvPackage ? import ../pkgs/direnv.nix { inherit pkgs; },
  # The JSON refers to its own hooks by this stable path, not by store path.
  managedDir ? "/etc/claude-code",
}:
let
  harnessLib = import ./default.nix { inherit lib; };

  hooks = import ./hooks.nix {
    inherit
      pkgs
      lib
      direnvPackage
      allowLocalCommits
      allowMemoryEdits
      enforcementRoots
      ;
  };

  settings = harnessLib.settings {
    managed = true;
    inherit
      platform
      allowLocalCommits
      allowMemoryEdits
      allowConnectors
      enforcementRoots
      extraDeny
      extraAllowedDomains
      allowManagedHooksOnly
      strictAllowlist
      extraKnownMarketplaces
      ;
    hookDir = "${managedDir}/hooks";
    marketplaceDir = "${managedDir}/plugins";
    mods = map (m: m.modName) mods;
    inherit marketplaceName;
  };
  settingsJson = (pkgs.formats.json { }).generate "managed-settings.json" settings;

  marketplaceName = "harness";
  marketplace = (import ./mods.nix { inherit pkgs lib; }).mkMarketplace {
    name = marketplaceName;
    owner = "claude-nix-harness";
    description = "Mods the harness ships to every session on this machine";
    inherit mods;
  };
in
pkgs.runCommand "claude-nix-harness-managed" { } ''
  mkdir -p $out
  cp ${settingsJson} $out/managed-settings.json
  cp -r ${hooks} $out/hooks
  cp -r ${marketplace} $out/plugins
''
