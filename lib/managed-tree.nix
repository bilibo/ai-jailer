# One store path: linked at /etc/claude-code on the host, or copied into a
# devenv-built container image.
{
  pkgs,
  lib,
  platform ? "linux",
  allowLocalCommits ? false,
  allowMemoryEdits ? false,
  enforcementRoots ? [ ],
  extraDeny ? [ ],
  extraAllowedDomains ? [ ],
  allowManagedHooksOnly ? true,
  strictAllowlist ? true,
  extraKnownMarketplaces ? [ ],
  direnvPackage ? import ../pkgs/direnv.nix { inherit pkgs; },
  # The JSON refers to its own hooks by this stable path, not by store path.
  managedDir ? "/etc/claude-code",
}:
let
  harnessLib = import ./default.nix { inherit lib; };

  mkHook =
    name: tools: extra:
    pkgs.replaceVarsWith {
      inherit name;
      src = ../hooks/${name};
      isExecutable = true;
      replacements = {
        path = lib.makeBinPath tools;
      }
      // extra;
    };

  envGuard =
    mkHook "env-guard.sh"
      [
        pkgs.jq
        direnvPackage
        pkgs.coreutils
        pkgs.diffutils
        pkgs.findutils
      ]
      {
        allowLocalCommits = if allowLocalCommits then "1" else "0";
        allowMemoryEdits = if allowMemoryEdits then "1" else "0";
        enforcementRoots = lib.concatStringsSep ":" enforcementRoots;
      };
  tmuxNotify = mkHook "tmux-notify.sh" [ pkgs.tmux ] { };

  settings = harnessLib.managedSettings {
    inherit
      platform
      allowLocalCommits
      allowMemoryEdits
      enforcementRoots
      extraDeny
      extraAllowedDomains
      allowManagedHooksOnly
      strictAllowlist
      extraKnownMarketplaces
      ;
    hookDir = "${managedDir}/hooks";
    marketplaceDir = "${managedDir}/plugins";
  };
  settingsJson = (pkgs.formats.json { }).generate "managed-settings.json" settings;
in
pkgs.runCommand "claude-harness-managed" { } ''
  mkdir -p $out/hooks $out/plugins/.claude-plugin
  cp ${settingsJson} $out/managed-settings.json
  cp ${envGuard} $out/hooks/env-guard.sh
  cp ${tmuxNotify} $out/hooks/tmux-notify.sh
  chmod 0555 $out/hooks/*
  # `#!/usr/bin/env bash` -> the store bash: the installed hook then depends
  # on nothing outside the store, and the tests run inside the Nix sandbox.
  patchShebangs $out/hooks
  # The broker mod lands here later (brief 5.7).
  cat > $out/plugins/.claude-plugin/marketplace.json <<'JSON'
  { "name": "harness", "owner": { "name": "claude-harness" }, "plugins": [] }
  JSON
''
