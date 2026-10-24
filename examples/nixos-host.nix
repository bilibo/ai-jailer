# The managed host shape: import the harness NixOS module into a
# nixos-config flake and set the two options it needs. Build-only material:
# `nix flake check` on the harness evaluates this module
# (checks.nixos-module-eval), and the human switches generations.
#
#   inputs.claude-nix-harness.url = "github:bilibo/claude-nix-harness";
#   ...
#   nixosConfigurations.work = nixpkgs.lib.nixosSystem {
#     modules = [ claude-nix-harness.nixosModules.harness ./nixos-host.nix ];
#   };
_: {
  harness.enable = true;
  # The Claude Code sandbox is bubblewrap; the module asserts this.
  security.allowUserNamespaces = true;
}
