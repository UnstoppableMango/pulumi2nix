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

      flake.lib = import ./lib;
      flake.overlays.default = import ./lib/overlay.nix;
      flake.flakeModules.default = ./modules/flake-module.nix;

      perSystem =
        { config, pkgs, ... }:
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

          checks = tools;

          devShells.default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              gnumake
              nixfmt
            ];
          };

          treefmt.programs = {
            nixfmt.enable = true;
          };
        };
    };
}
