# Mods: hooks modules the engine loads from the managed marketplace
# directory (docs/sessions.md section 5). A mod's source under `mods/` holds
# its hooks module, its types and its tests; the manifest
# (`.claude-plugin/plugin.json`) is written here from the attributes, so no
# `.claude-plugin` directory exists in the checkout: the deny rules keep an
# agent out of one, and `harness init` refuses a repo that carries one under
# `.claude`. The built plugin directory is what `claude plugin validate`,
# `claude plugin test` and `claude --plugin-dir` take (`nix build
# .#harness-broker`, then `result`).
{ pkgs, lib }:
let
  json = pkgs.formats.json { };
in
{
  # One plugin directory: the manifest, then `hooks/`, `types/` and `tests/`
  # from `src` where they exist. `hooks/hooks.json` must exist.
  mkMod =
    {
      name,
      version,
      description,
      author,
      src,
    }:
    pkgs.runCommand "mod-${name}-${version}"
      {
        passthru = {
          modName = name;
          modVersion = version;
          modDescription = description;
        };
      }
      ''
        mkdir -p $out/.claude-plugin
        cp ${
          json.generate "plugin.json" {
            inherit name version description;
            author.name = author;
          }
        } \
          $out/.claude-plugin/plugin.json
        for d in hooks types tests; do
          if [ -d ${src}/$d ]; then cp -r ${src}/$d $out/$d; fi
        done
        test -f $out/hooks/hooks.json
      '';

  # The marketplace directory the managed tree ships at `$out/plugins`: every
  # mod by a relative path, which is what makes it count as the
  # organisation's (docs/sessions.md section 5). `mods` are mkMod outputs.
  mkMarketplace =
    {
      name,
      owner,
      description,
      mods ? [ ],
    }:
    let
      manifest = json.generate "marketplace.json" {
        inherit name description;
        owner.name = owner;
        plugins = map (m: {
          name = m.modName;
          source = "./${m.modName}";
          description = m.modDescription;
        }) mods;
      };
    in
    pkgs.runCommand "marketplace-${name}" { } ''
      mkdir -p $out/.claude-plugin
      cp ${manifest} $out/.claude-plugin/marketplace.json
      ${lib.concatMapStringsSep "\n" (m: "cp -r ${m} $out/${m.modName}") mods}
    '';
}
