# The devenv binary cache, for the root nix.conf. The single source:
# pkgs/harness.nix exports it to bootstrap (HARNESS_DEVENV_CACHE and
# HARNESS_DEVENV_KEY); scripts/install.sh keeps a literal copy because it
# runs before Nix exists.
{
  url = "https://devenv.cachix.org";
  key = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
}
