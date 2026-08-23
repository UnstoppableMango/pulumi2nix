{
  description = "Composable builders for Pulumi providers, packages, and language SDKs";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/triplet";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [
        inputs.treefmt-nix.flakeModule
        ./modules/flake-module.nix
      ];

      flake = {
        lib = import ./lib;
        overlays.default = import ./lib/overlay.nix;
        flakeModules.default = ./modules/flake-module.nix;
      };

      perSystem =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          overlaidPkgs = pkgs.extend (import ./lib/overlay.nix);
          tools = {
            pulumi-language-dotnet = config.pulumi.lib.pulumiLanguageDotnet;
            # Exercises flake.overlays.default itself, not just flake.lib's curried-builder path.
            # Same build recipe/output as pulumi-language-dotnet above, so this proves the
            # overlay wires a real derivation without paying for a second build.
            overlay-pulumi-language-dotnet = overlaidPkgs.pulumiLanguageDotnet;
          };
        in
        {
          # Every example declares itself through the flake module's options,
          # which is what populates packages/checks below.
          imports = [ ./examples ];

          packages = tools // {
            default = pkgs.linkFarm "pulumi2nix-examples" config.pulumi.packages;
          };

          checks = tools // {
            # A unit check rather than another example: narrowing is pure `lib`
            # work on a `src`, and no example can reach it because they all take
            # the default fetch's pass-through branch.
            narrow-sdk-src = import ./checks/narrow-sdk-src.nix {
              inherit lib pkgs;
              inherit (config.pulumi.lib) narrowSdkSrc;
            };

            # Same reasoning, for the `sourceRoot` name the same `src` resolves
            # to. Kept separate from narrow-sdk-src so a failure names which of
            # the two decisions went wrong.
            src-name = import ./checks/src-name.nix {
              inherit lib pkgs;
              inherit (config.pulumi.lib) srcName;
            };

            # Filtered to .nix files so an unrelated README edit doesn't rebuild it.
            nix-lint =
              let
                nixFiles = lib.fileset.toSource {
                  root = ./.;
                  fileset = lib.fileset.fileFilter (file: file.hasExt "nix") ./.;
                };
              in
              pkgs.runCommandLocal "nix-lint"
                {
                  nativeBuildInputs = with pkgs; [
                    statix
                    deadnix
                  ];
                }
                ''
                  statix check ${nixFiles}
                  deadnix --fail ${nixFiles}
                  touch $out
                '';
          };

          devShells.default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              deadnix
              gnumake
              nixfmt
              statix
            ];
          };

          treefmt.programs = {
            nixfmt.enable = true;
          };
        };
    };
}
