# The two hook scripts as one store path, for the managed tree
# (/etc/claude-code/hooks); the repo settings no longer point at it.
{
  pkgs,
  lib,
  direnvPackage,
  allowLocalCommits ? false,
  allowMemoryEdits ? false,
}:
let
  mkHook =
    name: src: tools: extra:
    pkgs.replaceVarsWith {
      inherit name src;
      isExecutable = true;
      replacements = {
        path = lib.makeBinPath tools;
      }
      // extra;
    };

  envGuard =
    mkHook "env-guard.sh" ../hooks/env-guard.sh
      [
        pkgs.jq
        direnvPackage
        pkgs.coreutils
        pkgs.diffutils
        pkgs.findutils
        pkgs.gnugrep
        pkgs.gnused
      ]
      {
        allowLocalCommits = if allowLocalCommits then "1" else "0";
        allowMemoryEdits = if allowMemoryEdits then "1" else "0";
      };
  tmuxNotify = mkHook "tmux-notify.sh" ../hooks/tmux-notify.sh [ pkgs.tmux ] { };
in
pkgs.runCommand "ai-jailer-hooks" { } ''
  mkdir -p $out
  cp ${envGuard} $out/env-guard.sh
  cp ${tmuxNotify} $out/tmux-notify.sh
  chmod 0555 $out/*
  # `#!/usr/bin/env bash` -> the store bash: the hook depends on nothing
  # outside the store, and the tests run inside the Nix sandbox.
  patchShebangs $out
''
