# A worker's sandbox gets no agent and no key files, so it cannot push,
# clone or ssh as the user; the user's own shells keep both, and so does the
# jailer, who runs without the sandbox.
#
# Unix sockets are allowed wholesale in the sandbox (go-plugin, Nix daemon),
# so the agent socket is reachable; what keeps a session from signing is not
# knowing its address. GIT_SSH_COMMAND is deliberately absent: the sandbox
# sets its own for its proxy.
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
