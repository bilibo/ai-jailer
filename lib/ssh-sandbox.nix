# A sandboxed session in a jail (every work repo) gets no agent and
# no key files, so it cannot push, clone or ssh as the user, while the
# user's own shells keep both. The center runs without the sandbox, so its
# key files stay readable (settings.nix drops `filesystem` there). A
# project rule, not a universal one: outside the enforcement roots a session
# keeps the agent, and a hardware key's touch is the gate for the user's
# own pushes (README, "Git over SSH").
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
