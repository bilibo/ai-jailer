# The SSH rule as a sandbox fragment: a session in a harness repo gets no
# agent and no key files, so it cannot push, clone or ssh as the user, while
# the user's own shells keep both. It is a project rule, not a universal one:
# outside the enforcement roots a session keeps the agent, and a hardware
# key's touch is the gate for personal pushes (README, "Git over SSH").
#
# Two places include it, which together cover every harness repo:
#   - project-settings.nix: the .claude/settings.json devenv writes into each
#     repo. Deny entries merge across settings scopes and no scope can remove
#     one, so a repo-level entry holds against user and local settings.
#   - managed-settings.nix, only when the host enforces everywhere (empty
#     enforcementRoots), the same split deny-rules.nix uses.
#
# Unix sockets are allowed wholesale in the sandbox (go-plugin, Nix daemon),
# so the agent socket is reachable; what keeps a session from signing is not
# knowing its address. GIT_SSH_COMMAND is deliberately absent: the sandbox
# sets its own for its proxy. The Read-tool deny and the hook's credential
# regex keep covering ~/.ssh everywhere.
{
  filesystem.denyRead = [ "~/.ssh" ];
  credentials.envVars = [
    {
      name = "SSH_AUTH_SOCK";
      mode = "deny";
    }
    {
      name = "SSH_AGENT_PID";
      mode = "deny";
    }
  ];
}
