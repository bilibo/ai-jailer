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
      harnessLib = pkgs: import ./lib { inherit (pkgs) lib; };
      managedTree =
        pkgs: args:
        import ./lib/managed-tree.nix (
          {
            inherit pkgs;
            inherit (pkgs) lib;
          }
          // args
        );
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
          # (`harness bootstrap` does this). The same direnv the hooks
          # call, the same devenv the modules assume.
          direnv = direnvPackage;
          inherit (pkgs) devenv;
          # A dedicated work host: every rule everywhere.
          managed = managedTree pkgs { };
          # A mixed host: project rules only under the roots.
          managed-scoped = managedTree pkgs {
            enforcementRoots = [ "~/code/git" ];
            strictAllowlist = false;
          };
          # What the devenv module writes into a repo, with default options;
          # `/repo` stands for the checkout path devenv passes.
          project-settings = (pkgs.formats.json { }).generate "claude-settings.json" (
            (harnessLib pkgs).projectSettings {
              hookDir = "${hooks}";
              repoRoot = "/repo";
            }
          );
          # The same with the read fence on (`harness.readFence = true`).
          project-settings-fenced = (pkgs.formats.json { }).generate "claude-settings-fenced.json" (
            (harnessLib pkgs).projectSettings {
              hookDir = "${hooks}";
              repoRoot = "/repo";
              readFence = true;
              extraAllowRead = [ "~/.cargo" ];
            }
          );
          # bin/ccmux and bin/ccode (the former name).
          ccmux = import ./pkgs/ccmux.nix { inherit pkgs; };
          ccode = self.packages.${pkgs.stdenv.hostPlatform.system}.ccmux;
          # bin/harness: bootstrap, upgrade, doctor, init, check, reset.
          harness = import ./pkgs/harness.nix {
            inherit pkgs;
            rev = self.rev or self.dirtyRev or "dirty";
          };
          default = self.packages.${pkgs.stdenv.hostPlatform.system}.managed;
        }
      );

      # `nix fmt`: nixfmt over every .nix file (treefmt-wrapped).
      formatter = forAll (pkgs: pkgs.nixfmt-tree);

      # `nix run .#harness -- doctor`; `harness check` lives here rather than in
      # the checks, it needs the API.
      apps = forAll (pkgs: {
        harness = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.harness}/bin/harness";
          meta.description = "claude-nix-harness host tooling: bootstrap, upgrade, doctor, init, check, reset";
        };
      });

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
          hook-test-scoped =
            test "hook-test-scoped" ./tests/hook-test.sh
              "${p.managed-scoped}/hooks/env-guard.sh";
          project-settings-test =
            test "project-settings-test" ./tests/project-settings-test.sh
              "${p.project-settings}";
          project-settings-fenced-test =
            test "project-settings-fenced-test" ./tests/project-settings-test.sh
              "${p.project-settings-fenced} fenced";
          ccmux-test = test "ccmux-test" ./tests/ccmux-test.sh "${p.ccmux}/bin/ccmux";
          ccode-test = test "ccode-test" ./tests/ccmux-test.sh "${p.ccmux}/bin/ccode";
          # No nix, claude or code in the build sandbox: the MISSING case.
          harness-doctor-test =
            test "harness-doctor-test" ./tests/harness-doctor-test.sh
              "${p.harness}/bin/harness ${p.project-settings}";
          harness-init-dry-run-test =
            test "harness-init-dry-run-test" ./tests/harness-init-test.sh
              "${p.harness}/bin/harness";
        }
      );
    };
}
