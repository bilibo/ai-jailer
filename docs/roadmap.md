# Roadmap

What exists, what is next, and ideas that are not committed to. Numbers in
parentheses refer to sections of the original build brief.

## Done

- NixOS module: managed settings, hook, sandbox, mod policy, directory
  scoping, per-host options (5.2)
- home-manager module: direnv, tmux, `ccode` (5.1, without the broker signal)
- devenv module: generated project settings, host check, optional image (new)
- Hook unit tests, 149 cases (part of 5.6)
- Test repo: azfn-rust-handler, verified through the Functions host
- Framework laptop config cleanup, trusted-users, direnv 2.38

## Next, in order

1. **Activate on this laptop.** `nh os boot`, reboot, run the live checks in
   the runbook against the test repo. This is the first time a real
   session runs under the managed settings.
2. **devenv-base repo with the `azure` module** (5.3): `az` pin, Terraform
   with azurerm/azuread/alz providers, tflint, trivy, and the
   `AZURE_CONFIG_DIR` task under `.git/devenv-base/azure` shared by
   worktrees. `imports: - devenv-base/azure` resolves to
   `azure/devenv.nix`, same rule as `harness/devenv`.
3. **Repo template** (5.4): the test repo minus Rust, plus the azure module.
   Convert one real customer repo; confirm `az account show` and
   `terraform plan` inside the sandbox with the network allowlist, and
   record the exact blob hosts the first `terraform init` and `trivy` run
   need.
4. **Reader-only service principal per customer** (7.1). The one control
   that holds against every client, including things the hook never sees.
   Human logs it into the repo's `AZURE_CONFIG_DIR`.
5. **Live verification suite** (5.6): the runbook's manual checks as a
   script, run against a throwaway repo, one case per hard limit. Include
   the `.devenv/shell-*.sh` litter count over 50 commands.
6. **WSL host**: a second host in this flake with nixos-wsl, `harness.enable`
   only, and the WSL-specific checks (`/run/WSL` and `/mnt/c` empty inside
   the sandbox, `cmd.exe` fails).
7. **Broker mod** (5.7): observe-only, `/fleet` table from a file under
   `$XDG_RUNTIME_DIR`, deployed through the managed marketplace directory,
   `claude plugin validate` output as the contract. Only after everything
   above is boring.

## Open questions

- Notification hook: the matcher names (`permission_prompt`, `idle_prompt`,
  `elicitation_dialog`) come from the docs index, not verified live. If the
  window never turns orange, that is the first suspect.
- FileChanged matcher syntax: assumed to be a file-name pattern.
- `AZURE_CONFIG_DIR` shared across worktrees (7.2): MSAL lock contention is
  a known risk; revisit if two sessions switch subscriptions under each
  other.
- Per-command env evaluation cost (7.3): measure once the azure module is
  in; the SessionStart-only variant is the fallback.

## Ideas, not planned

- Tighten the hook with the gaps listed in the runbook's known-gaps section:
  gh and package publishing as project rules, git exec-vector config keys,
  az transfer verbs, and a fail-closed rule for dynamic shell constructs
  (`$IFS`, `$(`, `base64 -d |`) inside the enforcement roots. Each one
  starts as a test case.
- Remote Control (`claude remote-control`): the driven session is the local
  process, so managed settings, hook and sandbox apply unchanged; what
  changes is that anyone holding the claude.ai account can prompt a machine
  with work credentials nearby. Per-host opt-in, off on the work host until
  the broker and the verification suite exist; check whether managed
  settings can disable it outright.
- nix-darwin module: same `lib/`, managed settings under
  `/Library/Application Support/ClaudeCode/`, seatbelt sandbox keys.
- `harness.container.enable` for a project that must not touch the host at
  all: devenv builds it, podman runs it with `--security-opt unmask=/proc/*`
  so bubblewrap works inside. Known to need `--userns=keep-id` and the
  user-level podman socket when launched from `vscode-fhs`.
- A parser-based second guard (cc-safety-net rulebooks) beside the regex
  hook (7.6).
- Split `harness/` into its own repo: `git subtree split --prefix=harness`,
  add a `flake.nix` exporting `nixosModules.default`, `homeModules.default`,
  and the devenv module path.
