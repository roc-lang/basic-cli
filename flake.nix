{
  description = "Basic cli devShell flake";

  inputs = {
    roc.url = "github:roc-lang/roc";

    nixpkgs.follows = "roc/nixpkgs";

    # rust from nixpkgs has some libc problems, this is patched in the rust-overlay
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # to easily make configs for multiple architectures
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, roc, rust-overlay, flake-utils }:
    let supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    in flake-utils.lib.eachSystem supportedSystems (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };

        rocPkgs = roc.packages.${system};
        llvmPkgs = pkgs.llvmPackages_16;

        # get current working directory
        cwd = builtins.toString ./.;
        rust =
          pkgs.rust-bin.fromRustupToolchainFile "${toString ./rust-toolchain.toml}";

        aliases = ''
          alias buildcmd='bash jump-start.sh && roc ./build.roc -- --roc roc'
          alias testcmd='export ROC=roc && export EXAMPLES_DIR=./examples/ && ./ci/all_tests.sh'
        '';

        linuxInputs = with pkgs;
          lib.optionals stdenv.isLinux [
            valgrind
          ];

        darwinInputs = with pkgs;
          lib.optionals stdenv.isDarwin
          (with pkgs.darwin.apple_sdk.frameworks; [
            Security
          ]);

        sharedInputs = (with pkgs; [
          sqlite
          jq
          rust
          llvmPkgs.clang
          llvmPkgs.lldb # for debugging
          expect
          nmap
          simple-http-server
          rocPkgs.cli
          ripgrep # for ci/check_all_exposed_funs_tested.roc
        ]);
      in {

        devShell = pkgs.mkShell {
          buildInputs = sharedInputs ++ darwinInputs ++ linuxInputs;

          # nix does not store libs in /usr/lib or /lib
          # for libgcc_s.so.1
          NIX_LIBGCC_S_PATH =
            if pkgs.stdenv.isLinux then "${pkgs.stdenv.cc.cc.lib}/lib" else "";
          # for crti.o, crtn.o, and Scrt1.o
          NIX_GLIBC_PATH =
            if pkgs.stdenv.isLinux then "${pkgs.glibc.out}/lib" else "";

          shellHook = ''
            ${aliases}
            
            echo "Some convenient command aliases:"
            echo "${aliases}" | grep -E "alias [^=]+" -o | sed 's/alias /  /' | sort
            echo ""
          '';
        };

        formatter = pkgs.nixpkgs-fmt;
      });
}