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
            overlay-pulumi-language-dotnet = overlaidPkgs.pulumiLanguageDotnet;
          };
        in
        {
          imports = [ ./examples ];

          packages = tools // {
            default = pkgs.linkFarm "pulumi2nix-examples" config.pulumi.packages;
          };

          checks = tools // {
            narrow-sdk-src = import ./checks/narrow-sdk-src.nix {
              inherit lib pkgs;
              inherit (config.pulumi.lib) narrowSdkSrc;
            };

            src-name = import ./checks/src-name.nix {
              inherit lib pkgs;
              inherit (config.pulumi.lib) srcName;
            };

            sdk-omit-deps = pkgs.runCommandLocal "sdk-omit-deps" { } ''
              pkg=${config.packages.pulumi-command-sdk-nodejs}/lib/node_modules/@pulumi/command
              test -f "$pkg/index.js"

              if [ -e "$pkg/node_modules/@pulumi/pulumi" ]; then
                echo "sdk-omit-deps: SDK output bundles its own @pulumi/pulumi" >&2
                exit 1
              fi

              touch $out
            '';

            dynamic-bridge-version = pkgs.runCommandLocal "dynamic-bridge-version" { } ''
              want=v1.1.3
              got=$(${lib.getExe config.packages.pulumi-terraform-provider} --version)

              if [ "$got" != "$want" ]; then
                echo "dynamic-bridge-version: binary reports '$got', expected '$want'" >&2
                echo "(a 40-character SHA here means the version ldflag fell back to \`rev\`)" >&2
                exit 1
              fi

              touch $out
            '';

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
