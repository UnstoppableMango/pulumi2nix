# Integration coverage against unmango/pulumipkgs, pulumi2nix's largest consumer.
#
# This is a sibling flake rather than an input of the root one because pulumipkgs
# already declares `inputs.pulumi2nix`, so depending on it from the root flake
# would be a cycle. `integration -> {pulumi2nix, pulumipkgs} -> pulumi2nix` is
# still a DAG, which is what buys the coverage back.
#
# It checks two directions at once:
#
#   1. pulumipkgs' own packages, re-evaluated against this working tree, so a
#      breaking change to `lib`'s surface fails here instead of downstream.
#   2. pulumi2nix's own component examples, resolved against pulumipkgs'
#      `pulumiPackages` scope instead of nixpkgs'.
#
# Run it through the root Makefile (`make integration`), which supplies the
# `--override-input` that points `pulumi2nix` at the working tree.
{
  description = "Integration coverage for pulumi2nix against unmango/pulumipkgs";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/triplet";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    # Pinned to the published flake so `flake.lock` stays stable across commits.
    # Every entry point overrides it onto the working tree:
    #   nix flake check ./integration --override-input pulumi2nix .
    # Without the override this still evaluates, it just tests the last release
    # rather than what you are about to push.
    pulumi2nix = {
      url = "github:UnstoppableMango/pulumi2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # This `follows` is what makes the flake a downstream canary rather than a
    # smoke test: pulumipkgs' package set is re-evaluated against whichever
    # pulumi2nix the override supplies, so an API break surfaces as a failed
    # `pulumipkgs-*` check.
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
          # Resolves every builder against pulumipkgs' `pulumiPackages` scope
          # instead of nixpkgs'. `pkgs.pulumi` (the CLI) still comes from
          # nixpkgs: pulumipkgs ships plugins and language hosts, not a CLI.
          _module.args.pkgs = inputs'.pulumipkgs.legacyPackages;

          # The only two examples that take a `languagePlugin`. The bridge and
          # native-provider examples pass none, so they would cost build time
          # and add no coverage here.
          imports = [
            "${inputs.pulumi2nix}/examples/test-component"
            "${inputs.pulumi2nix}/examples/test-component-schema"
          ];

          # nodejs and go need no override: pulumipkgs re-exports nixpkgs' own
          # `pulumi-nodejs`/`pulumi-go` definitions under the same names, so the
          # examples resolve unchanged. dotnet is the one language host that
          # genuinely differs, because nixpkgs has no build at all and the
          # example falls back to `pulumi2nix.pulumiLanguageDotnet`.
          #
          # This is the check the flake was worth writing for. Upstream's
          # `getLogo()` (pulumi-language-dotnet/codegen/gen.go) downloads
          # logo.png, which the build sandbox forbids, so codegen only works
          # against a language host carrying the offline-logo patch. pulumipkgs
          # now ships its own copy of that patch, and this check is what notices
          # if a version bump ever drops it. The two builds are not otherwise
          # interchangeable: pulumipkgs pins 3.112.1 against the 3.110.0 in
          # lib/pulumi-language-dotnet.nix.
          pulumi.componentPackages.test-component.sdks.dotnet.languagePlugin =
            lib.mkForce pkgs.pulumiPackages.pulumi-dotnet;

          # A representative slice of pulumipkgs' package set: `command`
          # exercises mkPulumiPackage, `random` and `terraform-provider`
          # exercise mkTerraformBridgeProvider. Those are the only two builders
          # pulumipkgs consumes (see its pkgs/default.nix). Widen by adding
          # names from pulumipkgs' pkgs/plugins.
          checks = lib.mapAttrs' (name: lib.nameValuePair "pulumipkgs-${name}") {
            inherit (inputs'.pulumipkgs.packages) command random terraform-provider;
          };
        };
    };
}
