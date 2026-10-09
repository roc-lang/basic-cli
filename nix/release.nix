{ pkgs }:
let
  release = builtins.fromJSON (builtins.readFile ./release.json);
  # Must compile the pinned release, so bump it with release.json, not with the
  # nightly used for development.
  compiler = pkgs.rocpkgs."nightly-2026-09-26-d6267b4";
  bundle = pkgs.fetchurl { inherit (release) url hash; };
  unpack =
    name: archive:
    pkgs.runCommand name { nativeBuildInputs = [ pkgs.zstd ]; } ''
      mkdir -p "$out"
      tar --zstd -xf ${archive} -C "$out"
      test -f "$out/main.roc"
    '';
  platform = (unpack "basic-cli-${release.version}" bundle).overrideAttrs {
    passthru = {
      inherit release dependencies compiler;
      dependencyReplacements = replacements;
    };
  };
  dependencies = builtins.mapAttrs (
    name: dependency: unpack "roc-${name}" (pkgs.fetchurl { inherit (dependency) url hash; })
  ) release.dependencies;
  replacements = pkgs.lib.concatStringsSep " " (
    pkgs.lib.mapAttrsToList (
      name: dependency:
      "--replace-dep ${pkgs.lib.escapeShellArg dependency.url} ${dependencies.${name}}/main.roc"
    ) release.dependencies
  );
in
{
  packages = {
    inherit bundle platform;
    default = platform;
  };
  checks.consumer =
    pkgs.runCommand "basic-cli-consumer"
      {
        nativeBuildInputs = [ platform.compiler ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        cp ${pkgs.replaceVars ./consumer.roc { platformUrl = release.url; }} main.roc
        # Older releases can produce warnings with the pinned compiler. Roc
        # exits 2 after a successful build with warnings; still run the binary.
        roc build main.roc --output=hello \
          --replace-dep ${pkgs.lib.escapeShellArg release.url} ${platform}/main.roc \
          ${platform.dependencyReplacements} || test "$?" -eq 2
        ./hello > actual
        echo 'Hello from basic-cli!' > expected
        diff -u expected actual
        mkdir -p "$out/bin"
        cp hello "$out/bin/hello"
      '';
}
