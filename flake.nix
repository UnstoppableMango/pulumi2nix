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
      imports = [ inputs.treefmt-nix.flakeModule ];

      flake.lib = import ./lib { };
      flake.overlays.default = import ./lib/overlay.nix;

      perSystem =
        { pkgs, ... }:
        let
          flakeLib = import ./lib { };
          examples = import ./examples {
            inherit pkgs;
            nixpkgsPath = inputs.nixpkgs;
            inherit flakeLib;
          };
          overlaidPkgs = pkgs.extend (import ./lib/overlay.nix);
          tools = {
            pulumi-language-dotnet = flakeLib.pulumiLanguageDotnet { inherit pkgs; };
            # Exercises flake.overlays.default itself, not just flake.lib's
            # curried-builder path. Same build recipe/output as
            # pulumi-language-dotnet above (the overlay only touches
            # lib/default.nix's own attrs, not buildGoModule/fetchFromGitHub),
            # so this proves the overlay wires a real, buildable derivation
            # without paying for a second build.
            overlay-pulumi-language-dotnet = overlaidPkgs.pulumiLanguageDotnet;
          };
        in
        {
          packages =
            examples
            // tools
            // {
              default = pkgs.linkFarm "pulumi2nix-examples" examples;
            };

          checks = examples // tools;

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
