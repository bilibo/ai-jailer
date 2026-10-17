{
  description = "claude-harness: guard-railed, project-scoped Claude Code for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      managedTree = pkgs: args: import ./lib/managed-tree.nix ({ inherit pkgs; inherit (pkgs) lib; } // args);
    in
    {
      # NixOS side: harness.* -> /etc/claude-code (managed settings, hooks, mod policy).
      nixosModules.harness = ./nixos;
      nixosModules.default = self.nixosModules.harness;

      # home-manager side: devenv, direnv, tmux, programs.claude-code, `ccode`.
      homeModules.harness = ./home;
      homeModules.default = self.homeModules.harness;
      homeManagerModules = self.homeModules;

      # Pure helpers (deny rules, managed and project settings) for other
      # module systems, e.g. a future nix-darwin module.
      lib = import ./lib { inherit (nixpkgs) lib; };

      packages = forAll (pkgs: {
        # The managed tree with the defaults: a dedicated work host, every
        # rule everywhere.  nix build .#managed && cat result/managed-settings.json
        managed = managedTree pkgs { };
        # As a personal machine builds it: project rules only under the roots.
        managed-scoped = managedTree pkgs {
          enforcementRoots = [ "~/code/git" ];
          strictAllowlist = false;
        };
        ccode = import ./pkgs/ccode.nix { inherit pkgs; };
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.managed;
      });

      # `nix flake check`: the hook's unit tests against both managed trees
      # (the out-of-root section only runs with roots set) and the ccode
      # resolver tests.
      checks = forAll (
        pkgs:
        let
          system = pkgs.stdenv.hostPlatform.system;
          p = self.packages.${system};
          test =
            name: script: args:
            pkgs.runCommand name
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.jq # hook-test.sh builds its JSON cases with jq
                ];
              }
              ''
              export HOME=$TMPDIR
              bash ${script} ${args} | tee $out
            '';
        in
        {
          hook-test = test "hook-test" ./tests/hook-test.sh "${p.managed}/hooks/env-guard.sh";
          hook-test-scoped = test "hook-test-scoped" ./tests/hook-test.sh "${p.managed-scoped}/hooks/env-guard.sh";
          ccode-test = test "ccode-test" ./tests/ccode-test.sh "${p.ccode}/bin/ccode";
        }
      );
    };
}
