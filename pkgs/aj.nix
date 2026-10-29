# aj <command>: the unmanaged-host tooling behind one entry point.
# bootstrap, upgrade, doctor and reset are pkgs/aj/bootstrap.sh, init is
# init.sh, check is check.sh. Each body is its own writeShellApplication, so
# shellcheck covers it at build time; this wrapper only resolves the ai-jailer
# ref and dispatches. scripts/install.sh runs it once the root steps are done.
{
  pkgs,
  # The unit tests `aj init` runs on a new repo's generated file and hook.
  # Only this directory, not the whole flake source: the package then rebuilds
  # when the scripts or the tests change, not on every edit in the checkout.
  tests ? ../tests,
  rev ? "dirty",
  # The ref of last resort for `nix profile add` and devenv.yaml: the
  # published repo, never this package's own store path (garbage collection
  # would remove what the profile and the repos point at).
  defaultRef ? "github:bilibo/ai-jailer",
}:
let
  inherit (pkgs) lib;
  devenvCache = import ./devenv-cache.nix;
  # Prepended to the caller's PATH (inheritPath), so sudo, nix, claude, code,
  # dnf, rpm, systemctl, semanage, tmux and bwrap still come from the host.
  runtimeInputs = with pkgs; [
    coreutils
    findutils
    gnugrep
    gnused
    gawk
    jq
    git
  ];
  body =
    name: excludeShellChecks:
    pkgs.writeShellApplication {
      name = "aj-${name}";
      # The files' own `# shellcheck disable=` lines no longer come first once
      # writeShellApplication puts its PATH line above them.
      inherit runtimeInputs excludeShellChecks;
      bashOptions = [ ]; # each body sets its own; check.sh runs without errexit
      text = lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ./aj/${name}.sh);
    };
  bootstrap = body "bootstrap" [
    "SC1091"
    "SC2015"
    "SC2016"
    "SC2088"
  ];
  init = body "init" [ "SC2016" ];
  check = body "check" [ "SC2016" ];
in
pkgs.writeShellApplication {
  name = "aj";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.jq
  ];
  runtimeEnv = {
    AI_JAILER_REV = rev;
    AI_JAILER_TESTS = "${tests}";
    AI_JAILER_DEFAULT_REF = defaultRef;
    # bootstrap writes these into the user's direnv and tmux config;
    # host-config-test asserts the same files.
    AI_JAILER_DIRENV_TOML = "${./direnv.toml}";
    AI_JAILER_TMUX_CONF = "${./tmux.conf}";
    # The devenv cache bootstrap puts into nix.conf (pkgs/devenv-cache.nix).
    AI_JAILER_DEVENV_CACHE = devenvCache.url;
    AI_JAILER_DEVENV_KEY = devenvCache.key;
  };
  text = ''
    usage() {
      cat <<'EOF'
    usage: aj <command> [--dry-run] [--yes] [--verbose] [options]

      bootstrap   set this host up (scripts/install.sh runs it once Nix is there)
      upgrade     bootstrap, and move the profile packages to the ai-jailer ref's current lock
      doctor      every host prerequisite, claude doctor, and the jail in the cwd
      init        a jail: <org>/<repo> under the code root, or a path
      check       the live checks in a jail (claude -p sessions; costs API calls)
      reset       remove what bootstrap put on this host, from the receipt

      --dry-run   print each step, run none (never sudo)
      --yes       no confirmation prompt
      --verbose   print each command before it runs
      --version   the ai-jailer revision (before the command only)

    aj <command> --help has the details.
    EOF
    }

    # The flake `nix profile add` and devenv.yaml name: AI_JAILER_REF, else the
    # receipt's, else the published repo. --jailer, parsed by the bodies,
    # wins over all of them.
    resolve_ref() {
      local r
      if [ -n "''${AI_JAILER_REF:-}" ]; then AI_JAILER_REF_FROM=AI_JAILER_REF; return; fi
      r=$(jq -r '.jailer.ref // empty' "$HOME/.local/state/ai-jailer/receipt.json" 2>/dev/null || true)
      if [ -n "$r" ]; then AI_JAILER_REF=$r; AI_JAILER_REF_FROM=receipt; return; fi
      AI_JAILER_REF="$AI_JAILER_DEFAULT_REF"; AI_JAILER_REF_FROM=default
    }

    # This wrapper's store path: `upgrade` compares it with the profile's
    # after the profile upgrade and hands the user steps to the new one.
    export AI_JAILER_SELF
    AI_JAILER_SELF=$(readlink -f "$0")

    # Shared flags may also come before the command.
    shared=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --dry-run|--yes|--verbose) shared+=("$1"); shift ;;
        --version) echo "aj $AI_JAILER_REV"; exit 0 ;;
        -h|--help|help) usage; exit 0 ;;
        *) break ;;
      esac
    done
    [ $# -gt 0 ] || { usage >&2; exit 64; }
    cmd="$1"; shift
    case "$cmd" in
      bootstrap|upgrade|doctor|reset|init) resolve_ref; export AI_JAILER_REF AI_JAILER_REF_FROM ;;
    esac
    case "$cmd" in
      bootstrap|upgrade|doctor|reset) AI_JAILER_CMD="$cmd" exec ${bootstrap}/bin/aj-bootstrap "''${shared[@]}" "$@" ;;
      init) exec ${init}/bin/aj-init "''${shared[@]}" "$@" ;;
      check) exec ${check}/bin/aj-check "''${shared[@]}" "$@" ;;
      *) echo "aj: unknown command $cmd (see aj --help)" >&2; exit 64 ;;
    esac
  '';
  meta = {
    description = "ai-jailer host tooling: bootstrap, upgrade, doctor, init, check, reset";
    mainProgram = "aj";
  };
}
