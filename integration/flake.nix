{
  description = "Integration coverage for pulumi2nix against unmango/pulumipkgs";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/triplet";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    pulumi2nix = {
      url = "github:UnstoppableMango/pulumi2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pulumipkgs = {
      url = "github:unmango/pulumipkgs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pulumi2nix.follows = "pulumi2nix";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [ inputs.pulumi2nix.flakeModules.default ];

      perSystem =
        {
          inputs',
          lib,
          pkgs,
          ...
        }:
        {
          _module.args.pkgs = inputs'.pulumipkgs.legacyPackages;

          imports = [
            "${inputs.pulumi2nix}/examples/test-component"
            "${inputs.pulumi2nix}/examples/test-component-schema"
          ];

          pulumi.componentPackages.test-component.sdks.dotnet.languagePlugin =
            lib.mkForce pkgs.pulumiPackages.pulumi-dotnet;

          checks = lib.mapAttrs' (name: lib.nameValuePair "pulumipkgs-${name}") {
            inherit (inputs'.pulumipkgs.packages) command random terraform-provider;
          };
        };
    };
}
