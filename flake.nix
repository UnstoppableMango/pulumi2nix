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

      perSystem =
        { pkgs, ... }:
        let
          flakeLib = import ./lib { };
          examples = import ./examples {
            inherit pkgs;
            nixpkgsPath = inputs.nixpkgs;
            inherit flakeLib;
          };
          tools = {
            pulumi-language-dotnet = flakeLib.pulumiLanguageDotnet { inherit pkgs; };
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
