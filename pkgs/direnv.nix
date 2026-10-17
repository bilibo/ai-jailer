# direnv >= 2.38 adds `require_allowed`, the only way to re-block an .envrc
# when devenv.nix / devenv.yaml / devenv.lock change. nixpkgs still ships
# 2.37.1 (checked 2026-10-17). The modules only use it while pkgs.direnv is
# older than 2.38, but lib/managed-tree.nix defaults to it unconditionally:
# change that default to pkgs.direnv when dropping this file.
{ pkgs }:
pkgs.direnv.overrideAttrs (old: rec {
  version = "2.38.2";
  src = pkgs.fetchFromGitHub {
    owner = "direnv";
    repo = "direnv";
    tag = "v${version}";
    hash = "sha256-0TVuQ0TEqkkCo36zrdFbfZ+FJSVrvNA7egAcsS9YFtA=";
  };
  vendorHash = "sha256-3ojb8iLIzhjUZa7Gt+gJjOFy9qm4LOrFBLZ6fk5x1HM=";
})
