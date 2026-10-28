{
  description = "ai-jailer: guard-railed Claude Code for any Linux host with Nix, set up from this checkout";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      jailerLib = pkgs: import ./lib { inherit (pkgs) lib; };
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
      # For other module systems, e.g. a future nix-darwin module.
      lib = import ./lib { inherit (nixpkgs) lib; };

      packages = forAll (
        pkgs:
        let
          direnvPackage = pkgs.direnv;
          # Host-wide options for the managed tree (lib/managed-tree.nix's
          # arguments: allowLocalCommits, allowMemoryEdits, allowConnectors,
          # extraDeny, extraAllowedDomains, allowManagedHooksOnly,
          # extraKnownMarketplaces, direnvPackage, platform) from an optional
          # host.nix at the checkout root: an attrset, or a function of pkgs.
          # Gitignored: it is one host's policy. A `path:<checkout>` ref, which
          # bootstrap uses from a checkout, carries it; a `github:` ref never
          # sees it and builds the defaults. An unknown key fails evaluation.
          hostArgs =
            if builtins.pathExists ./host.nix then
              (
                let
                  h = import ./host.nix;
                in
                if builtins.isFunction h then h pkgs else h
              )
            else
              { };
        in
        {
          # Host tools, pinned by this flake's lock:
          # `nix profile add path:<checkout>#direnv path:<checkout>#devenv`
          # (`aj bootstrap` does this). The same direnv the hooks
          # call, the same devenv the devenv module assumes.
          direnv = direnvPackage;
          inherit (pkgs) devenv;
          # The managed tree: the law (managed-settings.json, every user), the
          # jail (jail-settings.json, the workers' reference body) and the
          # hooks. Bootstrap links `managed-wsl` where it detects WSL (the
          # Windows side hidden from the sandbox), `managed` elsewhere.
          managed = managedTree pkgs hostArgs;
          managed-wsl = managedTree pkgs (hostArgs // { platform = "wsl"; });
          # What the devenv module writes into a repo, with default options;
          # `/repo` stands for the checkout path devenv passes.
          project-settings = (pkgs.formats.json { }).generate "claude-settings.json" (
            (jailerLib pkgs).projectSettings {
              repoRoot = "/repo";
            }
          );
          # The same with the read fence on (`ai-jail.readFence = true`).
          project-settings-fenced = (pkgs.formats.json { }).generate "claude-settings-fenced.json" (
            (jailerLib pkgs).projectSettings {
              repoRoot = "/repo";
              readFence = true;
              extraAllowRead = [ "~/.cargo" ];
            }
          );
          # The same at a real-looking path: aj init runs the test on the
          # file devenv wrote for the actual repo, never at /repo.
          project-settings-elsewhere = (pkgs.formats.json { }).generate "claude-settings-elsewhere.json" (
            (jailerLib pkgs).projectSettings {
              repoRoot = "/home/acme/code/git/acme/demo";
            }
          );
          ajmux = import ./pkgs/ajmux.nix { inherit pkgs; };
          # bin/aj: bootstrap, upgrade, doctor, init, check, reset.
          aj = import ./pkgs/aj.nix {
            inherit pkgs;
            rev = self.rev or self.dirtyRev or "dirty";
          };
          default = self.packages.${pkgs.stdenv.hostPlatform.system}.managed;
        }
        # claude-code is unfree: exported, like the check below, only when the
        # evaluator allows it. The devenv module uses the same file.
        // pkgs.lib.optionalAttrs (builtins.tryEval pkgs.claude-code.outPath).success {
          # pkgs.claude-code without the LD_LIBRARY_PATH its wrapper leaks
          # into every hook, command and MCP server (pkgs/claude-code.nix),
          # for a host that installs Claude Code from this flake.
          claude-code = import ./pkgs/claude-code.nix { inherit pkgs; };
        }
      );

      # `nix fmt`: nixfmt over every .nix file (treefmt-wrapped).
      formatter = forAll (pkgs: pkgs.nixfmt-tree);

      # `nix run .#aj -- doctor`; `aj check` lives here rather than in
      # the checks, it needs the API.
      apps = forAll (pkgs: {
        aj = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.aj}/bin/aj";
          meta.description = "ai-jailer host tooling: bootstrap, upgrade, doctor, init, check, reset";
        };
        default = self.apps.${pkgs.stdenv.hostPlatform.system}.aj;
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
          # The managed tree with every host.nix option set, as a host would
          # set it; managed-host-eval reads the settings it renders.
          hostTree = managedTree pkgs {
            allowLocalCommits = true;
            allowMemoryEdits = true;
            allowConnectors = true;
            extraDeny = [ "Bash(x)" ];
            extraAllowedDomains = [ "example.com" ];
            extraKnownMarketplaces = [ "example-market" ];
            allowManagedHooksOnly = false;
          };
          # The devenv module under lib.evalModules, not devenv: stand-ins
          # for the devenv options it sets or reads, the checkout at /repo.
          # The file it would write, its packages and its enterShell as JSON.
          devenvRender =
            name: jail:
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
                        config.ai-jail = jail;
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
          ajmux-test = test "ajmux-test" ./tests/ajmux-test.sh "${p.ajmux}/bin/ajmux";
          hook-test-worktree =
            test "hook-test-worktree" ./tests/hook-test.sh
              "${stubHooks}/env-guard.sh --direnv-stub";
          host-config-test =
            test "host-config-test" ./tests/host-config-test.sh
              "${./pkgs/direnv.toml} ${./pkgs/tmux.conf}";
          # The pre-Nix script with its host commands stubbed: installer, Fedora and NixOS routes.
          install-test = test "install-test" ./tests/install-test.sh "${./scripts/install.sh}";
          # No nix, claude or code in the build sandbox: the MISSING case.
          aj-doctor-test =
            test "aj-doctor-test" ./tests/aj-doctor-test.sh
              "${p.aj}/bin/aj ${p.project-settings}";
          # bootstrap, doctor and reset on a stubbed non-Fedora host.
          aj-bootstrap-test = test "aj-bootstrap-test" ./tests/aj-bootstrap-test.sh "${p.aj}/bin/aj";
          aj-init-dry-run-test =
            test "aj-init-dry-run-test" ./tests/aj-init-test.sh
              "${p.aj}/bin/aj ${p.project-settings}";
          # `aj check` judges tool results, never the model's prose.
          check-parser-test =
            test "check-parser-test" ./tests/check-parser-test.sh
              "${p.aj}/bin/aj ${./tests/fixtures}";
          # The host.nix options reach the managed tree: a tree with every
          # option set against the default one, and the WSL variant hides the
          # Windows side. The rule options land in the jail, the managed-only
          # keys in the law (roadmap item 14).
          managed-host-eval = pkgs.runCommand "managed-host-eval" { nativeBuildInputs = [ pkgs.jq ]; } ''
            d=${p.managed}/managed-settings.json
            dj=${p.managed}/jail-settings.json
            wj=${p.managed-wsl}/jail-settings.json
            h=${hostTree}/managed-settings.json
            hj=${hostTree}/jail-settings.json
            jq -e '.permissions.deny | index("Bash(x)") and index("Bash(git commit)") == null' "$hj"
            jq -e '.permissions.deny | index("Bash(x)") == null and index("Bash(git commit)")' "$dj"
            jq -e '.permissions.deny | index("Bash(x)") == null and index("Bash(git commit)") == null and index("Bash(git push)")' "$h"
            jq -e '.permissions.deny | index("Bash(git commit)") and index("Bash(git push)")' "$d"
            jq -e '.sandbox.network.allowedDomains | index("example.com")' "$hj"
            jq -e '.sandbox.network.allowedDomains | index("example.com") == null' "$dj"
            jq -e 'has("sandbox") | not' "$h"
            jq -e '.disableClaudeAiConnectors == false' "$hj"
            jq -e '.disableClaudeAiConnectors == true' "$dj"
            jq -e '(has("allowManagedHooksOnly") | not) and .strictKnownMarketplaces == ["example-market"]' "$h"
            jq -e '.allowManagedHooksOnly == true and .strictKnownMarketplaces == []' "$d"
            grep -q 'ALLOW_MEMORY_EDITS="1"' ${hostTree}/hooks/env-guard.sh
            grep -q 'ALLOW_MEMORY_EDITS="0"' ${p.managed}/hooks/env-guard.sh
            jq -e '.sandbox.filesystem.denyRead | index("/mnt/c") and index("/run/WSL")' "$wj"
            jq -e '.sandbox.filesystem.denyRead | index("/mnt/c") == null' "$dj"
            echo "managed-host-eval: host options and the wsl variant render as expected" | tee $out
          '';
          # The devenv module writes the project layer only: no hooks, no deny
          # rule but extraDeny, the two sandbox belt scalars and never
          # `sandbox.enabled` (the jail's), the seven literal
          # denyWrite paths under the checkout (/repo), the project domains,
          # the read fence when on, `settings` merged in. enterShell checks
          # for the managed file and exports AI_JAIL_PROJECT, never
          # AI_JAILER_ROLE. `enable = false`: no file, no AI_JAILER_* export, the
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
              jq -e "$S"' s | (has("hooks") | not) and (.sandbox | has("enabled") | not) and .sandbox.allowUnsandboxedCommands == false' "$f"
              jq -e --argjson want "$protected" "$S"' s.sandbox.filesystem.denyWrite == $want' "$f"
            done
            jq -e "$S"' s | .permissions.deny == [] and (.permissions | has("allow") | not)' "$on"
            jq -e "$S"' s.sandbox | .network.allowedDomains == [] and (.filesystem | has("denyRead") or has("allowRead") | not)' "$on"
            jq -e "$S"' s | .permissions.deny == ["Bash(x)"] and .permissions.allow == ["Bash(terraform plan *)"]' "$extra"
            jq -e "$S"' s.sandbox.network.allowedDomains == ["example.com"]' "$extra"
            jq -e "$S"' s.sandbox.filesystem | .denyRead == ["~/"] and (.allowRead | index("~/.cargo") and index("/repo"))' "$fenced"
            jq -e '.enterShell | test("export AI_JAIL_PROJECT=") and test("/etc/claude-code/managed-settings.json is missing") and (test("AI_JAILER_ROLE") | not)' "$on"
            jq -e '.files == {}' "$off"
            jq -e '.enterShell | test("guard rails off for this repo") and (test("AI_JAILER_") | not)' "$off"
            jq -e '.packages == ["ajmux"]' "$on"
            jq -e '.packages == ["ajmux"]' "$off"
            jq -e '.packages == ["ajmux", "claude-code", "tmux", "jq"]' "$tools"
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
          # pkgs/claude-code.nix: no LD_LIBRARY_PATH in the wrapper, the binary
          # unpatched, and it still starts.
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
