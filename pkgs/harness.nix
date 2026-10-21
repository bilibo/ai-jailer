# harness <command>: the unmanaged-host tooling behind one entry point.
# bootstrap, upgrade, doctor and reset are pkgs/harness/bootstrap.sh, init is
# init.sh, check is check.sh. Each body is its own writeShellApplication, so
# shellcheck covers it at build time; this wrapper only resolves the harness
# ref and dispatches. scripts/install.sh runs it once the root steps are done.
{
  pkgs,
  # The unit tests `harness init` runs on a new repo's generated file and hook.
  # Only this directory, not the whole flake source: the package then rebuilds
  # when the scripts or the tests change, not on every edit in the checkout.
  tests ? ../tests,
  rev ? "dirty",
  # The ref of last resort for `nix profile add` and devenv.yaml: the
  # published repo, never this package's own store path (garbage collection
  # would remove what the profile and the repos point at).
  defaultRef ? "github:bilibo/claude-nix-harness",
}:
let
  inherit (pkgs) lib;
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
      name = "harness-${name}";
      # The files' own `# shellcheck disable=` lines no longer come first once
      # writeShellApplication puts its PATH line above them.
      inherit runtimeInputs excludeShellChecks;
      bashOptions = [ ]; # each body sets its own; check.sh runs without errexit
      text = lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ./harness/${name}.sh);
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
  name = "harness";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.jq
  ];
  runtimeEnv = {
    HARNESS_REV = rev;
    HARNESS_TESTS = "${tests}";
    HARNESS_DEFAULT_REF = defaultRef;
    # bootstrap appends these to the user's direnv and tmux config; the home
    # module and install.sh read the same files.
    HARNESS_DIRENV_TOML = "${./direnv.toml}";
    HARNESS_TMUX_CONF = "${./tmux.conf}";
  };
  text = ''
    usage() {
      cat <<'EOF'
    usage: harness <command> [--dry-run] [--yes] [--verbose] [options]

      bootstrap   set this host up (scripts/install.sh runs it once Nix is there)
      upgrade     bootstrap, and move the profile packages to the harness ref's current lock
      doctor      every host prerequisite, claude doctor, and the harness repo in the cwd
      init        a harness repo: <customer>/<repo> under the code root, or a path
      check       the live checks in a harness repo (claude -p sessions; costs API calls)
      reset       remove what bootstrap put on this host, from the receipt

      --dry-run   print each step, run none (never sudo)
      --yes       no confirmation prompt
      --verbose   print each command before it runs
      --version   the harness revision

    harness <command> --help has the details.
    EOF
    }

    # The flake `nix profile add` and devenv.yaml name: HARNESS_REF, else the
    # receipt's, else the profile's ccmux entry (a host bootstrapped before
    # receipts), else the published repo. --harness, parsed by the bodies,
    # wins over all of them.
    resolve_ref() {
      local r
      if [ -n "''${HARNESS_REF:-}" ]; then HARNESS_REF_FROM=HARNESS_REF; return; fi
      r=$(jq -r '.harness.ref // empty' "$HOME/.local/state/claude-nix-harness/receipt.json" 2>/dev/null || true)
      if [ -n "$r" ]; then HARNESS_REF=$r; HARNESS_REF_FROM=receipt; return; fi
      if command -v nix >/dev/null 2>&1; then
        r=$(nix profile list --json 2>/dev/null \
          | jq -r '.elements | if type == "object" then .ccmux.originalUrl // empty else map(select((.attrPath // "") | endswith(".ccmux"))) | .[0].originalUrl // empty end' 2>/dev/null || true)
        if [ -n "$r" ]; then HARNESS_REF=$r; HARNESS_REF_FROM="nix profile"; return; fi
      fi
      HARNESS_REF="$HARNESS_DEFAULT_REF"; HARNESS_REF_FROM=default
    }

    # Shared flags may also come before the command.
    shared=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --dry-run|--yes|--verbose) shared+=("$1"); shift ;;
        --version) echo "harness $HARNESS_REV"; exit 0 ;;
        -h|--help|help) usage; exit 0 ;;
        *) break ;;
      esac
    done
    [ $# -gt 0 ] || { usage >&2; exit 64; }
    cmd="$1"; shift
    case "$cmd" in
      bootstrap|upgrade|doctor|reset|init) resolve_ref; export HARNESS_REF HARNESS_REF_FROM ;;
    esac
    case "$cmd" in
      bootstrap|upgrade|doctor|reset) HARNESS_CMD="$cmd" exec ${bootstrap}/bin/harness-bootstrap "''${shared[@]}" "$@" ;;
      init) exec ${init}/bin/harness-init "''${shared[@]}" "$@" ;;
      check) exec ${check}/bin/harness-check "''${shared[@]}" "$@" ;;
      *) echo "harness: unknown command $cmd (see harness --help)" >&2; exit 64 ;;
    esac
  '';
  meta = {
    description = "claude-nix-harness host tooling: bootstrap, upgrade, doctor, init, check, reset";
    mainProgram = "harness";
  };
}
