{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default-linux";
    crane.url = "github:ipetkov/crane";
    flake-compat.url = "github:edolstra/flake-compat";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      imports = [
        inputs.treefmt-nix.flakeModule
      ];

      perSystem =
        {
          pkgs,
          lib,
          system,
          ...
        }:
        let
          rust = pkgs.rust-bin.fromRustupToolchainFile ./rust/rust-toolchain.toml;
          craneLib = (inputs.crane.mkLib pkgs).overrideToolchain rust;
          overlays = [ inputs.rust-overlay.overlays.default ];

          src = lib.cleanSource ./rust;
          nativeBuildInputs = [
            # Compiler & Runtime
            rust # Rust
            pkgs.godotPackages_4_4.godot # Godot4

            # Build tools
            pkgs.pkg-config # pkg-config

            # LSP
            pkgs.nil
          ];

          cargoArtifacts = craneLib.buildDepsOnly {
            inherit src nativeBuildInputs;
          };
          wayland-gdext-rs = craneLib.buildPackage {
            inherit
              src
              cargoArtifacts
              nativeBuildInputs
              ;
            strictDeps = true;
            doCheck = true;

            meta = {
              licenses = [ lib.licenses.mit ];
            };
          };
          cargo-clippy = craneLib.cargoClippy {
            inherit
              src
              cargoArtifacts
              nativeBuildInputs
              ;
            cargoClippyExtraArgs = "--verbose -- --deny warnings";
          };
          cargo-doc = craneLib.cargoDoc {
            inherit
              src
              cargoArtifacts
              nativeBuildInputs
              ;
          };
        in
        {
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system overlays;
          };

          treefmt = {
            projectRootFile = "flake.nix";

            # Nix
            programs.nixfmt.enable = true;

            # Rust
            programs.rustfmt.enable = true;
            settings.formatter.rustfmt.command = "${rust}/bin/rustfmt";

            # TOML
            programs.taplo.enable = true;

            # GitHub Actions
            programs.actionlint.enable = true;

            # Markdown
            programs.mdformat.enable = true;

            # ShellScript
            programs.shellcheck.enable = true;
            programs.shfmt.enable = true;
          };

          packages = {
            inherit wayland-gdext-rs;
            default = wayland-gdext-rs;
            doc = cargo-doc;
          };

          checks = {
            inherit cargo-clippy;
          };

          devShells.default = pkgs.mkShell {
            inherit nativeBuildInputs;

            shellHook = ''
              export PS1="\n[nix-shell:\w]$ "
            '';
          };
        };
    };
}
