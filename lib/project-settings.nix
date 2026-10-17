# Carries the full deny set and the SSH rule because managed settings carry
# only the universal subset when the host scopes enforcement by directory.
# The agent cannot edit the file (Edit deny rule + hook), so inside the repo
# it holds as a belt to the hook's braces.
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
