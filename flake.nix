{
  description = "claude-nix-harness: project-scoped, guard-railed Claude Code for any host with Nix; NixOS adds the managed layer";

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
      nixosModules.harness = ./nixos;
      nixosModules.default = self.nixosModules.harness;

      homeModules.harness = ./home;
      homeModules.default = self.homeModules.harness;
      # Older name for the same outputs.
      homeManagerModules = self.homeModules;

      # For other module systems, e.g. a future nix-darwin module.
      lib = import ./lib { inherit (nixpkgs) lib; };

      packages = forAll (
        pkgs:
        let
          # The same fallback as the modules: pkgs.direnv once nixpkgs ships
          # >= 2.38, the override until then.
          direnvPackage =
            if pkgs.lib.versionOlder pkgs.direnv.version "2.38" then
              import ./pkgs/direnv.nix { inherit pkgs; }
            else
              pkgs.direnv;
          hooks = import ./lib/hooks.nix {
            inherit pkgs direnvPackage;
            inherit (pkgs) lib;
          };
        in
        {
          # Host tools for an unmanaged host, pinned by this flake's lock:
          # `nix profile add path:<checkout>#direnv path:<checkout>#devenv`
          # (scripts/bootstrap-fedora.sh does this). The same direnv the hooks
          # call, the same devenv the modules assume.
          direnv = direnvPackage;
          devenv = pkgs.devenv;
          # A dedicated work host: every rule everywhere.
          managed = managedTree pkgs { };
          # A mixed host: project rules only under the roots.
          managed-scoped = managedTree pkgs {
            enforcementRoots = [ "~/code/git" ];
            strictAllowlist = false;
          };
          # What the devenv module writes into a repo, with default options.
          project-settings = (pkgs.formats.json { }).generate "claude-settings.json" (
            (import ./lib { inherit (pkgs) lib; }).projectSettings { hookDir = "${hooks}"; }
          );
          # bin/ccmux and bin/ccode (the former name).
          ccmux = import ./pkgs/ccmux.nix { inherit pkgs; };
          ccode = self.packages.${pkgs.stdenv.hostPlatform.system}.ccmux;
          default = self.packages.${pkgs.stdenv.hostPlatform.system}.managed;
        }
      );

      # The hook's out-of-root cases only run with roots set, hence both trees.
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
                  pkgs.jq # the tests build and inspect JSON with jq
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
          project-settings-test = test "project-settings-test" ./tests/project-settings-test.sh "${p.project-settings}";
          ccmux-test = test "ccmux-test" ./tests/ccmux-test.sh "${p.ccmux}/bin/ccmux";
          ccode-test = test "ccode-test" ./tests/ccmux-test.sh "${p.ccmux}/bin/ccode";
        }
      );
    };
}
