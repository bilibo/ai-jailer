# Project-scope .claude/settings.json for a repo under the harness: the full
# deny set (managed settings carry only the universal subset when the host
# scopes enforcement by directory), the SSH sandbox rule (same split) and
# the worktree setting. The agent cannot edit this file (Edit deny rule +
# hook), so it holds as a belt to the hook's braces inside the repo.
{ lib }:
{
  allowLocalCommits ? false,
  allowMemoryEdits ? false,
}:
let
  denyRules = import ./deny-rules.nix { inherit lib; };
in
{
  "$schema" = "https://json.schemastore.org/claude-code-settings.json";
  permissions = {
    defaultMode = "default";
    deny = denyRules { inherit allowLocalCommits allowMemoryEdits; };
  };
  # Sandbox deny entries merge across scopes and cannot be removed by a lower
  # one, so this holds from the repo even though the sandbox itself is
  # configured in managed settings.
  sandbox = import ./ssh-sandbox.nix;
  worktree.baseRef = "head";
}
