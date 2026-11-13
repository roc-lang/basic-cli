{
  description = "basic-cli release platform and development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # nixos-unstable no longer supports Intel macOS.
    nixpkgs-x86-darwin.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    roc-overlay = {
      url = "github:roc-lang/roc-overlay/67491987eb6ef2423d9a6e5901f6a8e439d8566c";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs-darwin.follows = "nixpkgs-x86-darwin";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-x86-darwin,
      roc-overlay,
      rust-overlay,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = lib.genAttrs supportedSystems;
      rustToolchainConfig = (builtins.fromTOML (builtins.readFile ./rust-toolchain.toml)).toolchain;

      # scripts/build.py cross-compiles the host with `zig cc` for the musl
      # targets, so those work from any host. The macOS targets need an Apple
      # SDK for the bundled C dependencies, so only ship their standard
      # libraries where they can actually be built.
      muslRustTargets = [
        "x86_64-unknown-linux-musl"
        "aarch64-unknown-linux-musl"
      ];
      darwinRustTargets = [
        "x86_64-apple-darwin"
        "aarch64-apple-darwin"
      ];
      rustTargetsFor =
        system: muslRustTargets ++ lib.optionals (lib.hasSuffix "-darwin" system) darwinRustTargets;
      pkgsFor =
        system:
        import (if system == "x86_64-darwin" then nixpkgs-x86-darwin else nixpkgs) {
          inherit system;
          overlays = [
            roc-overlay.overlays.default
            # Until roc-overlay records the November 13 nightly.
            (import ./nix/roc-nightly.nix)
            rust-overlay.overlays.default
          ];
        };
      releaseFor = system: import ./nix/release.nix { pkgs = pkgsFor system; };
      # Keep in sync with the nightly pinned in .github/workflows.
      developmentCompilerFor = system: (pkgsFor system).rocpkgs."nightly-2026-11-13-03dce41";
    in
    {
      formatter = forAllSystems (system: (pkgsFor system).nixfmt);

      packages = forAllSystems (system: (releaseFor system).packages);
      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          compiler = developmentCompilerFor system;
        in
        (releaseFor system).checks
        // {
          development-compiler = pkgs.runCommand "basic-cli-development-compiler" {
            nativeBuildInputs = [ compiler ];
          } ''
            test "$(roc version)" = "Roc compiler version ${compiler.version}"
            touch "$out"
          '';
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          rustToolchain = pkgs.rust-bin.fromRustupToolchain (
            rustToolchainConfig // { targets = rustTargetsFor system; }
          );
        in
        {
          default = pkgs.mkShell {
            packages = [
              (developmentCompilerFor system)
              pkgs.python3
              rustToolchain
              pkgs.simple-http-server
              pkgs.zig_0_16
            ]
            ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.valgrind ];
          };
        }
      );
    };
}
