# nixpkgs wraps `claude` with `--prefix LD_LIBRARY_PATH : <alsa-lib>/lib`.
# LD_LIBRARY_PATH is inherited by every hook, Bash command and MCP server
# a session starts, and on a host whose own binaries use the distro glibc,
# one that loads libasound (VS Code's `code`) gets the Nix copy, whose
# RUNPATH pulls the Nix glibc into a process already running the distro's,
# and dies (changelog 2026-10-24). This override removes that wrapper line
# and nothing else.
#
# The library served an embedded native addon (`bun-ant-audio-out`, linked
# against libasound.so.2) that the binary extracts and dlopens when audio
# output is used. Without the variable that dlopen fails and audio output
# does not work; the sandboxed sessions ai-jailer runs do not use it.
# Not replaced by a RUNPATH on the binary: `patchelf --add-rpath`, in any
# order with autoPatchelfHook's interpreter change, leaves claude-code
# 2.1.303 segfaulting on `--version` (changelog 2026-10-27; 2.1.308 was
# unaffected), and a RUNPATH on the executable would not have reached the
# addon's own dependencies anyway (ld.so searches the loading object's
# RUNPATH, not the executable's, for a dlopened library's NEEDED entries).
#
# The wrapper line is removed from installPhase and must be there to
# remove: when nixpkgs stops setting it, the assertion fails and this file
# goes, pkgs.claude-code taking its place (tests/claude-code-test.sh checks
# the result).
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
  }
)
