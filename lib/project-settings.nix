# The repo's .claude/settings.json, written by the devenv module. The full
# settings body without the managed-only keys (settings.nix): on a host
# without managed settings this file alone carries the deny rules, the hooks
# and the sandbox. The agent cannot edit it (Edit deny rule, hook, sandbox
# denyWrite, and it is a read-only store symlink), so inside the repo it
# holds as a belt to the hook's braces.
{ lib }:
{
  # Store path of lib/hooks.nix, built with empty enforcement roots.
  hookDir,
  platform ? "linux",
  allowLocalCommits ? false,
  allowMemoryEdits ? false,
  allowConnectors ? false,
  extraDeny ? [ ],
  extraAllowedDomains ? [ ],
}:
import ./settings.nix { inherit lib; } {
  managed = false;
  inherit
    hookDir
    platform
    allowLocalCommits
    allowMemoryEdits
    allowConnectors
    extraDeny
    extraAllowedDomains
    ;
}
