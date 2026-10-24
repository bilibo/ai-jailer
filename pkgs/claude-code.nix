# nixpkgs wraps `claude` with `--prefix LD_LIBRARY_PATH : <alsa-lib>/lib`:
# nothing links libasound, the binary dlopens it at runtime. LD_LIBRARY_PATH
# is inherited by every hook, Bash command and MCP server a session starts,
# and on a host whose own binaries use the distro glibc, one that loads
# libasound (VS Code's `code`) gets the Nix copy, whose RUNPATH pulls the
# Nix glibc into a process already running the distro's, and dies
# (changelog 2026-10-24). The scoped form of the same dependency is a
# RUNPATH on the binary: a dlopen from the executable's own code searches
# it, and no child ever sees it. autoPatchelfHook has already grown this
# Bun-compiled binary once (the interpreter), so patchelf is known to keep
# it working. The wrapper line is removed from installPhase and must be
# there to remove: when nixpkgs stops setting it, the assertion fails and
# this file goes, pkgs.claude-code taking its place (tests/claude-code-test.sh
# checks the result).
{ pkgs }:
let
  inherit (pkgs) lib;
  alsa = lib.makeLibraryPath [ pkgs.alsa-lib ];
  # The needle only: the match must not depend on the store path, and
  # `lib.hasInfix` (builtins.match underneath) refuses a string with context.
  line = builtins.unsafeDiscardStringContext "--prefix LD_LIBRARY_PATH : ${alsa} \\\n";
in
pkgs.claude-code.overrideAttrs (
  old:
  let
    replaced = builtins.replaceStrings [ line ] [ "" ] old.installPhase;
  in
  {
    installPhase =
      assert lib.assertMsg (replaced != old.installPhase)
        "pkgs/claude-code.nix: pkgs.claude-code ${old.version} no longer sets LD_LIBRARY_PATH in its wrapper; delete this override";
      replaced;
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.patchelf ];
    # After autoPatchelfHook's fixup, which sets the interpreter and would
    # not add a library nothing links.
    postFixup = (old.postFixup or "") + ''
      patchelf --add-rpath ${alsa} $out/bin/.claude-wrapped
    '';
  }
)
