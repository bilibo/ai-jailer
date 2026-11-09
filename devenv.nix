# The jailer's shell: the human runs `aj bootstrap` here (never a session)
# with this checkout as the ai-jailer ref, so the law, the jail, the CLI and
# the workers come from one revision and a host.nix here reaches the rules.
# Every ai-jail option is listed below, the unused ones commented out;
# devenv/devenv.nix has the descriptions.
{ config, pkgs, ... }:
{
  name = "ai-jailer";
  # The ref bootstrap, upgrade and init use; `path:` carries the untracked
  # host.nix.
  packages = [ (import ./pkgs/aj.nix { inherit pkgs; }) ];
  env.AI_JAILER_REF = "path:${config.devenv.root}";
  ai-jail = {
    # enable = false;                  # guard rails off for this repo: no project layer; the host's rules stay
    claudeCode.enable = true;
    # readFence = true;                # hide the rest of $HOME from sandboxed commands
    # extraAllowRead = [ "~/.cargo" ]; # with readFence: what the project reads under $HOME
    # allowConnectors = true;          # claude.ai connectors, MCP servers outside the sandbox
    # platform = "wsl";                # hides /mnt/c and /run/WSL from the sandbox
    # extraDeny = [ "Bash(az devops *)" ];
    # extraAllowedDomains = [ "dev.azure.com" ];              # project hosts, merged into the sandbox allowlist
    # settings.permissions.allow = [ "Bash(terraform plan *)" ];
  };
}
