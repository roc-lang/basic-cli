# Temporary supplement until roc-overlay records this nightly. Reuse its
# installation and wrapping recipe, with the official archives and digests.
final: prev:
let
  source = (builtins.fromJSON (builtins.readFile ./roc-nightly-sources.json)).${prev.stdenv.hostPlatform.system};
  tag = builtins.elemAt (prev.lib.splitString "/" source.url) 7;
in
{
  rocpkgs = prev.rocpkgs // {
    ${tag} = prev.rocpkgs.default.overrideAttrs (old: {
      version = tag;
      src = final.fetchurl source;
      passthru = old.passthru // {
        inherit tag source;
        compilerVersion = tag;
        compilerCommit = "d5a4f1e9e128359a8d4d3caea40fe3ba7e6eb1e2";
      };
      meta = old.meta // {
        changelog = "https://github.com/roc-lang/nightlies/releases/tag/${tag}";
      };
    });
  };
}
