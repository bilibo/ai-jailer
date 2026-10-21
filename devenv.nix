# This repo is its own harnessed project and the template install.sh users
# clone: Claude Code and tmux come from this shell. It is also the command
# center (docs/roadmap.md, "Target flow"): the session here accepts what
# project sessions propose. Every option a project devenv.nix can set is
# listed below, the unused ones commented out; devenv/devenv.nix has the
# descriptions. The hook refuses this file from a session: edit it by hand.
_: {
  name = "claude-nix-harness";
  harness = {
    claudeCode.enable = true;
    # Auto-memory under ~/.claude/projects/<slug>/memory stays writable;
    # nothing else under ~/.claude opens up.
    allowMemoryEdits = true;
    # allowLocalCommits = true;        # commits on the worktree branch; push stays impossible
    # readFence = true;                # hide the rest of $HOME from sandboxed commands (roadmap 2.1)
    # extraAllowRead = [ "~/.cargo" ]; # with readFence: what the project reads under $HOME
    # allowConnectors = true;          # claude.ai connectors, MCP servers outside the sandbox
    # platform = "wsl";                # hides /mnt/c and /run/WSL from the sandbox
    # extraDeny = [ "Bash(az devops *)" ];
    # extraAllowedDomains = [ "dev.azure.com" ];              # sandbox allowlist, unmanaged host only
    # settings.permissions.allow = [ "Bash(terraform plan *)" ];
  };
}
