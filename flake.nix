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
      # The mods this repository ships, built plugin directories (lib/mods.nix).
      mods =
        pkgs:
        import ./mods {
          inherit pkgs;
          inherit (pkgs) lib;
        };
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

      # For other module systems, e.g. a future nix-darwin module.
      lib = import ./lib { inherit (nixpkgs) lib; };

      packages = forAll (
        pkgs:
        let
          direnvPackage = import ./pkgs/direnv.nix { inherit pkgs; };
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
          # The work host once the broker mod ships: `harness.mods` set.
          managed-mods = managedTree pkgs { mods = [ (mods pkgs).harness-broker ]; };
          # The broker mod as a plugin directory: `claude plugin validate
          # --strict result`, `claude plugin test result`, `claude --plugin-dir
          # result` (mods/harness-broker/README.md).
          inherit (mods pkgs) harness-broker;
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
          # The same at a real-looking path: harness init runs the test on the
          # file devenv wrote for the actual repo, never at /repo.
          project-settings-elsewhere = (pkgs.formats.json { }).generate "claude-settings-elsewhere.json" (
            (harnessLib pkgs).projectSettings {
              hookDir = "${hooks}";
              repoRoot = "/home/acme/code/git/acme/demo";
            }
          );
          ccmux = import ./pkgs/ccmux.nix { inherit pkgs; };
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
          # The worktree .envrc auto-allow and the pre-command environment check
          # call direnv; this stand-in logs the calls and answers `status` and
          # `export` from env vars (hook-test.sh --direnv-stub).
          direnvStub = pkgs.writeShellScriptBin "direnv" ''
            echo "direnv $*" >> "''${DIRENV_STUB_LOG:-/dev/null}"
            case "$1" in
              status) printf '%s' "''${DIRENV_STUB_STATUS:-}" ;;
              export)
                if [ -n "''${DIRENV_STUB_EXPORT:-}" ]; then printf '%s' "$DIRENV_STUB_EXPORT"; else printf '{}'; fi
                [ -z "''${DIRENV_STUB_EXPORT_ERR:-}" ] || echo "''${DIRENV_STUB_EXPORT_ERR}" >&2
                exit "''${DIRENV_STUB_EXPORT_RC:-0}" ;;
            esac
          '';
          stubHooks = import ./lib/hooks.nix {
            inherit pkgs;
            inherit (pkgs) lib;
            direnvPackage = direnvStub;
          };
          # The NixOS module evaluated, never built into a system: only the
          # tree it links at /etc/claude-code is forced, and, for the
          # assertion, config.assertions, which needs no toplevel either.
          nixosConfig =
            allowUserNamespaces:
            (nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [
                self.nixosModules.harness
                {
                  nixpkgs.pkgs = pkgs;
                  harness.enable = true;
                  security.allowUserNamespaces = allowUserNamespaces;
                  system.stateVersion = "26.05";
                }
              ];
            }).config;
          managedEtc = (nixosConfig true).environment.etc."claude-code".source;
          harnessAssertion = pkgs.lib.findFirst (a: pkgs.lib.hasPrefix "harness:" a.message) null (
            builtins.filter (a: !a.assertion) (nixosConfig false).assertions
          );
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
          project-settings-root-test =
            test "project-settings-root-test" ./tests/project-settings-test.sh
              "${p.project-settings-elsewhere} /home/acme/code/git/acme/demo";
          ccmux-test = test "ccmux-test" ./tests/ccmux-test.sh "${p.ccmux}/bin/ccmux";
          hook-test-worktree =
            test "hook-test-worktree" ./tests/hook-test.sh
              "${stubHooks}/env-guard.sh --direnv-stub";
          host-config-test =
            test "host-config-test" ./tests/host-config-test.sh
              "${./pkgs/direnv.toml} ${./pkgs/tmux.conf}";
          # The pre-Nix script with its host commands stubbed, both routes.
          install-test = test "install-test" ./tests/install-test.sh "${./scripts/install.sh}";
          # No nix, claude or code in the build sandbox: the MISSING case.
          harness-doctor-test =
            test "harness-doctor-test" ./tests/harness-doctor-test.sh
              "${p.harness}/bin/harness ${p.project-settings}";
          # bootstrap, doctor and reset on a stubbed non-Fedora host.
          harness-bootstrap-test =
            test "harness-bootstrap-test" ./tests/harness-bootstrap-test.sh
              "${p.harness}/bin/harness";
          harness-init-dry-run-test =
            test "harness-init-dry-run-test" ./tests/harness-init-test.sh
              "${p.harness}/bin/harness ${p.project-settings}";
          # `harness check` judges tool results, never the model's prose.
          check-parser-test =
            test "check-parser-test" ./tests/check-parser-test.sh
              "${p.harness}/bin/harness ${./tests/fixtures}";
          # The module's managed tree: the sandbox block, the hook by its
          # stable path, the deny rules; and the user-namespace assertion.
          nixos-module-eval = pkgs.runCommand "nixos-module-eval" { nativeBuildInputs = [ pkgs.jq ]; } ''
            s=${managedEtc}/managed-settings.json
            jq -e '.sandbox.enabled == true and .sandbox.failIfUnavailable == true and .sandbox.allowUnsandboxedCommands == false and .sandbox.network.strictAllowlist == true' "$s"
            jq -e '[.hooks[][].hooks[].command] | length > 0 and all(startswith("/etc/claude-code/hooks/"))' "$s"
            jq -e '.permissions.deny | index("Bash(git push)") and index("Bash(nh os switch)")' "$s"
            test -x ${managedEtc}/hooks/env-guard.sh
            echo "nixos-module-eval: managed tree ${managedEtc}" | tee $out
          '';
          nixos-module-assertion = pkgs.runCommand "nixos-module-assertion" { } (
            if harnessAssertion == null then
              "echo 'security.allowUserNamespaces = false did not fire the harness assertion' >&2; exit 1"
            else
              "echo ${pkgs.lib.escapeShellArg harnessAssertion.message} | tee $out"
          );
          # The managed tree's mod wiring, with and without a mod.
          managed-tree-test =
            test "managed-tree-test" ./tests/managed-tree-test.sh
              "${p.managed-mods} ${p.managed} ${./mods}";
        }
        # claude-code is unfree in nixpkgs: the validate and plugin-test run
        # is a check only when the evaluator allows it (NIXPKGS_ALLOW_UNFREE=1
        # with --impure, or allowUnfree in the nixpkgs config); otherwise run
        # tests/mod-validate-test.sh by hand with the host's claude.
        // pkgs.lib.optionalAttrs (builtins.tryEval pkgs.claude-code.outPath).success {
          mod-validate-test =
            pkgs.runCommand "mod-validate-test"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.jq
                  pkgs.claude-code
                ];
              }
              ''
                export HOME=$TMPDIR
                bash ${./tests/mod-validate-test.sh} ${p.managed-mods}/plugins | tee $out
              '';
        }
      );
    };
}
