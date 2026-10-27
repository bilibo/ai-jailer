# This repo is its own jail and the control point for the host:
# the human runs `aj bootstrap` from this shell (never a session), with
# this checkout as the ai-jailer ref, so the managed rules at /etc/claude-code,
# the CLI and the workers come from one revision, and a host.nix here reaches
# the rules. Claude Code and tmux come from this shell too. Every option a
# project devenv.nix can set is listed below, the unused ones commented out;
# devenv/devenv.nix has the descriptions. The hook refuses this file from a
# session: edit it by hand.
{ config, pkgs, ... }:
{
  name = "ai-jailer";
  # The `aj` CLI built from this checkout, and the ref bootstrap, upgrade
  # and init use: `path:` carries untracked files such as host.nix.
  packages = [ (import ./pkgs/aj.nix { inherit pkgs; }) ];
  env.AI_JAILER_REF = "path:${config.devenv.root}";
  ai-jail = {
    claudeCode.enable = true;
    # readFence = true;                # hide the rest of $HOME from sandboxed commands (roadmap 2.1)
    # extraAllowRead = [ "~/.cargo" ]; # with readFence: what the project reads under $HOME
    # allowConnectors = true;          # claude.ai connectors, MCP servers outside the sandbox
    # platform = "wsl";                # hides /mnt/c and /run/WSL from the sandbox
    # extraDeny = [ "Bash(az devops *)" ];
    # extraAllowedDomains = [ "dev.azure.com" ];              # sandbox allowlist, unmanaged host only
    # settings.permissions.allow = [ "Bash(terraform plan *)" ];
  };
}
