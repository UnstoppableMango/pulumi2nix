{ }:
{
  # Wraps nixpkgs' own Go/Terraform-bridge Pulumi provider builder
  # (`pkgs/by-name/pu/pulumi/extra/mk-pulumi-package.nix`, found via
  # `nixpkgsPath`) and layers `withSdks` on top to add composable
  # per-language SDK builders (currently: nodejs) alongside the python SDK
  # nixpkgs already provides.
  mkPulumiPackage =
    { pkgs, nixpkgsPath }:
    pkgs.callPackage ./mk-pulumi-package.nix { inherit nixpkgsPath; };

  # The terraform-bridge base builder on its own, without any SDK layering.
  mkTerraformBridgeProvider =
    { pkgs, nixpkgsPath }:
    pkgs.callPackage ./mk-terraform-bridge-provider.nix {
      inherit nixpkgsPath;
      mkTerraformBridgeSchema = pkgs.callPackage ./mk-terraform-bridge-schema.nix {
        mkSchema = pkgs.callPackage ./mk-schema.nix { };
      };
    };

  # Builds only a terraform-bridge provider's generated schema.json, without
  # the resource provider binary or any SDKs.
  mkTerraformBridgeSchema =
    { pkgs }:
    pkgs.callPackage ./mk-terraform-bridge-schema.nix {
      mkSchema = pkgs.callPackage ./mk-schema.nix { };
    };

  # Same, but for native providers whose gen tool takes an explicit output
  # path and version flag instead of a "schema" subcommand.
  mkPulumiSchema =
    { pkgs }:
    pkgs.callPackage ./mk-pulumi-schema.nix {
      mkSchema = pkgs.callPackage ./mk-schema.nix { };
    };

  # Attaches `<lang>Args`-driven SDK builds to any base derivation's
  # `passthru.sdks`, not just a terraform-bridge one.
  withSdks =
    { pkgs }:
    pkgs.callPackage ./with-sdks.nix { sdkBuilders = pkgs.callPackage ./sdks { }; };

  # Registry of per-language SDK builders (lang name -> builder function),
  # for composing SDK builds directly without going through `withSdks`.
  sdkBuilders =
    { pkgs }:
    pkgs.callPackage ./sdks { };

  # nixpkgs has no `pulumi-language-dotnet` (unlike its `pulumi-language-
  # {go,nodejs,python}`) - a pinned build of it, for use as a
  # `pulumi package gen-sdk --language dotnet` plugin.
  pulumiLanguageDotnet =
    { pkgs }:
    pkgs.callPackage ./pulumi-language-dotnet.nix { };

  # Generates a language SDK's source tree on demand from a schema.json,
  # via `pulumi package gen-sdk`, for packages that don't ship one
  # upstream (e.g. component providers).
  mkGeneratedSdk =
    { pkgs }:
    pkgs.callPackage ./mk-generated-sdk.nix { };

  # Extracts schema.json from a source-based, multi-language component
  # provider (a folder with a PulumiPlugin.yaml) via `pulumi package
  # get-schema`, rather than building a separate `cmd/pulumi-gen-<name>`
  # tool the way mkPulumiSchema/mkTerraformBridgeSchema do.
  mkComponentSchema =
    { pkgs }:
    pkgs.callPackage ./mk-component-schema.nix { };
}
