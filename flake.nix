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

      # For other module systems, e.g. a future nix-darwin module.
      lib = import ./lib { inherit (nixpkgs) lib; };

      packages = forAll (
        pkgs:
        let
          direnvPackage = pkgs.direnv;
        in
        {
          # Host tools for an unmanaged host, pinned by this flake's lock:
          # `nix profile add path:<checkout>#direnv path:<checkout>#devenv`
          # (`harness bootstrap` does this). The same direnv the hooks
          # call, the same devenv the modules assume.
          direnv = direnvPackage;
          inherit (pkgs) devenv;
          # The managed tree: every rule, for every user on the host.
          managed = managedTree pkgs { };
          # What the devenv module writes into a repo, with default options;
          # `/repo` stands for the checkout path devenv passes.
          project-settings = (pkgs.formats.json { }).generate "claude-settings.json" (
            (harnessLib pkgs).projectSettings {
              repoRoot = "/repo";
            }
          );
          # The same with the read fence on (`harness.readFence = true`).
          project-settings-fenced = (pkgs.formats.json { }).generate "claude-settings-fenced.json" (
            (harnessLib pkgs).projectSettings {
              repoRoot = "/repo";
              readFence = true;
              extraAllowRead = [ "~/.cargo" ];
            }
          );
          # The same at a real-looking path: harness init runs the test on the
          # file devenv wrote for the actual repo, never at /repo.
          project-settings-elsewhere = (pkgs.formats.json { }).generate "claude-settings-elsewhere.json" (
            (harnessLib pkgs).projectSettings {
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
        # claude-code is unfree: exported, like the check below, only when the
        # evaluator allows it. The home and devenv modules use the same file.
        // pkgs.lib.optionalAttrs (builtins.tryEval pkgs.claude-code.outPath).success {
          # pkgs.claude-code without the LD_LIBRARY_PATH its wrapper leaks
          # into every hook, command and MCP server (pkgs/claude-code.nix),
          # for a host that installs Claude Code from this flake.
          claude-code = import ./pkgs/claude-code.nix { inherit pkgs; };
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
          # The NixOS module evaluated with `extra` merged in, never built
          # into a system: only the slices the checks read are forced (the
          # tree linked at /etc/claude-code, the worker users, groups, sudo
          # rule and substituters, config.assertions), none needs a
          # toplevel. The root filesystem and grub lines are what a toplevel
          # would need; they keep a forced one from failing on the fixture.
          # Home Manager is not an input of this flake, so `options ?
          # home-manager` is false here and the module's worker HM branch is
          # never evaluated; that branch is live check V6.
          nixosSystemWith =
            extra:
            nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [
                self.nixosModules.harness
                {
                  nixpkgs.pkgs = pkgs;
                  harness.enable = true;
                  system.stateVersion = "26.05";
                  fileSystems."/" = {
                    device = "x";
                    fsType = "ext4";
                  };
                  boot.loader.grub.enable = false;
                }
                extra
              ];
            };
          nixosConfig = extra: (nixosSystemWith extra).config;
          managedEtc = (nixosConfig { }).environment.etc."claude-code".source;
          workerFixture.harness = {
            owner = "raul";
            workers = {
              acme = {
                gitName = "Claude (acme)";
                gitEmail = "claude-acme@example.invalid";
              };
              beta = {
                uid = 1101;
                gitName = "Claude (beta)";
                gitEmail = "claude-beta@example.invalid";
                homeManager = false;
              };
            };
          };
          workerSystem = nixosSystemWith workerFixture;
          workerSlices =
            let
              c = workerSystem.config;
            in
            pkgs.writeText "nixos-workers.json" (
              builtins.toJSON {
                acme = {
                  inherit (c.users.users."w-acme")
                    group
                    extraGroups
                    homeMode
                    linger
                    ;
                };
                betaUid = c.users.users."w-beta".uid;
                acmeMembers = c.users.groups."w-acme".members;
                hasAgents = c.users.groups ? agents;
                sudoRules = c.security.sudo.extraRules;
                inherit (c.nix.settings) extra-substituters;
                etc = "${c.environment.etc."claude-code".source}";
                hasHomeManager = workerSystem.options ? home-manager;
                failed = map (a: a.message) (builtins.filter (a: !a.assertion) c.assertions);
              }
            );
          # Each case: module config and a substring of the first failing
          # `harness:` assertion message it must produce (nixos/default.nix).
          assertionCases = [
            {
              config.security.allowUserNamespaces = false;
              expect = "harness: the Claude Code sandbox (bubblewrap) needs security.allowUserNamespaces = true.";
            }
            {
              config = workerFixture // {
                nix.settings.trusted-users = [ "w-acme" ];
              };
              expect = "harness: worker users and their groups must not be in nix.settings.trusted-users: w-acme.";
            }
            {
              config = workerFixture // {
                nix.settings.trusted-users = [ "@agents" ];
              };
              expect = "harness: worker users and their groups must not be in nix.settings.trusted-users: @agents.";
            }
            {
              config.harness = { inherit (workerFixture.harness) workers; };
              expect = "harness: harness.workers is set, so harness.owner must name the human's login.";
            }
          ];
          harnessAssertion =
            extra:
            pkgs.lib.findFirst (a: pkgs.lib.hasPrefix "harness:" a.message) null (
              builtins.filter (a: !a.assertion) (nixosConfig extra).assertions
            );
          # The devenv module under lib.evalModules, not devenv: stand-ins
          # for the devenv options it sets or reads, the checkout at /repo.
          # The file it would write, its packages and its enterShell as JSON.
          devenvRender =
            name: harness:
            let
              c =
                (pkgs.lib.evalModules {
                  specialArgs = { inherit pkgs; };
                  modules = [
                    ./devenv/devenv.nix
                    (
                      { lib, ... }:
                      {
                        options = {
                          name = lib.mkOption {
                            type = lib.types.nullOr lib.types.str;
                            default = null;
                          };
                          devenv.root = lib.mkOption {
                            type = lib.types.str;
                            default = "/repo";
                          };
                          files = lib.mkOption {
                            type = lib.types.attrsOf (
                              lib.types.submodule { options.json = lib.mkOption { type = lib.types.attrs; }; }
                            );
                            default = { };
                          };
                          packages = lib.mkOption {
                            type = lib.types.listOf lib.types.package;
                            default = [ ];
                          };
                          enterShell = lib.mkOption {
                            type = lib.types.lines;
                            default = "";
                          };
                        };
                        config = { inherit harness; };
                      }
                    )
                  ];
                }).config;
            in
            pkgs.writeText "devenv-${name}.json" (
              builtins.toJSON {
                files = pkgs.lib.mapAttrs (_: f: f.json) c.files;
                packages = map pkgs.lib.getName c.packages;
                inherit (c) enterShell;
              }
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
          # The pre-Nix script with its host commands stubbed: installer, Fedora and NixOS routes.
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
          # stable path, the deny rules, the mod policy with no marketplace
          # directory. Then the worker fixture: users, groups, the owner's
          # sudo rule, the devenv substituter, no failed assertion, and no
          # Home Manager in the option tree (see nixosSystemWith).
          nixos-module-eval = pkgs.runCommand "nixos-module-eval" { nativeBuildInputs = [ pkgs.jq ]; } ''
            s=${managedEtc}/managed-settings.json
            jq -e '.sandbox.enabled == true and .sandbox.failIfUnavailable == true and .sandbox.allowUnsandboxedCommands == false and .syncClaudeAiSkills == false and .syncClaudeAiPlugins == false and (.sandbox.network | has("strictAllowlist") | not)' "$s"
            jq -e '[.hooks[][].hooks[].command] | length > 0 and all(startswith("/etc/claude-code/hooks/"))' "$s"
            jq -e '.permissions.deny | index("Bash(git push)") and index("Bash(nh os switch)")' "$s"
            jq -e '.allowManagedHooksOnly == true and .disableSideloadFlags == true and .strictKnownMarketplaces == [] and (has("enabledPlugins") or has("extraKnownMarketplaces") | not)' "$s"
            test -x ${managedEtc}/hooks/env-guard.sh
            test ! -e ${managedEtc}/plugins
            w=${workerSlices}
            jq -e '.acme.group == "w-acme" and (.acme.extraGroups | index("agents")) and .acme.homeMode == "0750" and .acme.linger == true' "$w"
            jq -e '.betaUid == 1101 and (.acmeMembers | index("raul") and index("w-acme")) and .hasAgents' "$w"
            jq -e '[.sudoRules[] | select(.runAs == "%agents")] | length == 1 and (.[0].users == ["raul"]) and (.[0].commands[0].options | index("NOPASSWD"))' "$w"
            jq -e '(."extra-substituters" | index("https://devenv.cachix.org")) and (.etc | startswith("${builtins.storeDir}/")) and .hasHomeManager == false and .failed == []' "$w"
            test -e "$(jq -r .etc "$w")/managed-settings.json"
            echo "nixos-module-eval: managed tree ${managedEtc}, workers ok" | tee $out
          '';
          nixos-module-assertion = pkgs.runCommand "nixos-module-assertion" { } (
            pkgs.lib.concatMapStrings (
              case:
              let
                a = harnessAssertion case.config;
              in
              if a == null || !pkgs.lib.hasInfix case.expect a.message then
                ''
                  echo ${pkgs.lib.escapeShellArg "expected: ${case.expect}"} >&2
                  echo ${pkgs.lib.escapeShellArg "got: ${if a == null then "no failed harness assertion" else a.message}"} >&2
                  exit 1
                ''
              else
                ''
                  echo ${pkgs.lib.escapeShellArg a.message} | tee -a $out
                ''
            ) assertionCases
          );
          # The devenv module writes the project layer only: no hooks, no deny
          # rule but extraDeny, the sandbox scalars, the seven literal
          # denyWrite paths under the checkout (/repo), the project domains,
          # the read fence when on, `settings` merged in. enterShell checks
          # for the managed file and exports HARNESS_PROJECT, never
          # HARNESS_ROLE. `enable = false`: no file, no HARNESS_* export, the
          # notice instead, the packages kept.
          devenv-module-eval = pkgs.runCommand "devenv-module-eval" { nativeBuildInputs = [ pkgs.jq ]; } ''
            on=${devenvRender "on" { }}
            fenced=${
              devenvRender "fenced" {
                readFence = true;
                extraAllowRead = [ "~/.cargo" ];
              }
            }
            off=${devenvRender "off" { enable = false; }}
            extra=${
              devenvRender "extra" {
                extraDeny = [ "Bash(x)" ];
                extraAllowedDomains = [ "example.com" ];
                settings.permissions.allow = [ "Bash(terraform plan *)" ];
              }
            }
            tools=${devenvRender "tools" { claudeCode.enable = true; }}
            S='def s: .files[".claude/settings.json"];'
            protected='["/repo/.git/hooks", "/repo/.git/config", "/repo/.claude/settings.json", "/repo/.claude/settings.local.json", "/repo/.claude/hooks", "/repo/.claude/skills", "/repo/.claude-plugin"]'
            for f in "$on" "$fenced" "$extra"; do
              jq -e "$S"' .files | keys == [".claude/settings.json"]' "$f"
              jq -e "$S"' s | (has("hooks") | not) and .sandbox.enabled == true' "$f"
              jq -e --argjson want "$protected" "$S"' s.sandbox.filesystem.denyWrite == $want' "$f"
            done
            jq -e "$S"' s | .permissions.deny == [] and (.permissions | has("allow") | not)' "$on"
            jq -e "$S"' s.sandbox | .network.allowedDomains == [] and (.filesystem | has("denyRead") or has("allowRead") | not)' "$on"
            jq -e "$S"' s | .permissions.deny == ["Bash(x)"] and .permissions.allow == ["Bash(terraform plan *)"]' "$extra"
            jq -e "$S"' s.sandbox.network.allowedDomains == ["example.com"]' "$extra"
            jq -e "$S"' s.sandbox.filesystem | .denyRead == ["~/"] and (.allowRead | index("~/.cargo") and index("/repo"))' "$fenced"
            jq -e '.enterShell | test("export HARNESS_PROJECT=") and test("/etc/claude-code/managed-settings.json is missing") and (test("HARNESS_ROLE") | not)' "$on"
            jq -e '.files == {}' "$off"
            jq -e '.enterShell | test("guard rails off for this repo") and (test("HARNESS_") | not)' "$off"
            jq -e '.packages == ["ccmux"]' "$on"
            jq -e '.packages == ["ccmux"]' "$off"
            jq -e '.packages == ["ccmux", "claude-code", "tmux", "jq"]' "$tools"
            echo "devenv-module-eval: defaults, read fence, extra rules, claudeCode and enable = false render as expected" | tee $out
          '';
          # The managed tree: the host-wide rules, runnable hooks, and the mod
          # policy (no mods shipped, every mod refused).
          managed-tree-test = test "managed-tree-test" ./tests/managed-tree-test.sh "${p.managed}";
        }
        # claude-code is unfree in nixpkgs: its check exists only when the
        # evaluator allows it (NIXPKGS_ALLOW_UNFREE=1 with --impure, or
        # allowUnfree in the nixpkgs config).
        // pkgs.lib.optionalAttrs (builtins.tryEval pkgs.claude-code.outPath).success {
          # pkgs/claude-code.nix: no LD_LIBRARY_PATH in the wrapper, alsa-lib
          # as a RUNPATH, and the binary still starts.
          claude-code-test =
            pkgs.runCommand "claude-code-test"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.patchelf
                  pkgs.binutils
                ];
              }
              ''
                bash ${./tests/claude-code-test.sh} ${p.claude-code} | tee $out
              '';
        }
      );
    };
}
