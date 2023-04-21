{
  description = "Basic cli devShell flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # rust from nixpkgs has some libc problems, this is patched in the rust-overlay
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # to easily make configs for multiple architectures
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, rust-overlay, flake-utils }:
    let supportedSystems = [ "x86_64-linux" "x86_64-darwin" "aarch64-darwin" ];
    in flake-utils.lib.eachSystem supportedSystems (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };

        llvmPkgs = pkgs.llvmPackages_13;

        # get current working directory
        cwd = builtins.toString ./.;
        rust =
          pkgs.rust-bin.fromRustupToolchainFile "${cwd}/src/rust-toolchain.toml";

        linuxInputs = with pkgs;
          lib.optionals stdenv.isLinux [
          ];

        darwinInputs = with pkgs;
          lib.optionals stdenv.isDarwin
          (with pkgs.darwin.apple_sdk.frameworks; [
          ]);

        sharedInputs = (with pkgs; [
          rust
          llvmPkgs.clang
          expect
          nmap
        ]);
      in {

        devShell = pkgs.mkShell {
          buildInputs = sharedInputs ++ darwinInputs ++ linuxInputs;

          # nix does not store libs in /usr/lib or /lib
          NIX_GLIBC_PATH =
            if pkgs.stdenv.isLinux then "${pkgs.glibc.out}/lib" else "";
        };

        formatter = pkgs.nixpkgs-fmt;
      });
}
