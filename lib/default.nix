{ }:
{
  # Wraps nixpkgs' own Go/Terraform-bridge Pulumi provider builder
  # (`pkgs/by-name/pu/pulumi/extra/mk-pulumi-package.nix`, found via
  # `nixpkgsPath`, which defaults to `pkgs.path`) and layers `withSdks` on
  # top to add composable per-language SDK builders (currently: nodejs)
  # alongside the python SDK nixpkgs already provides.
  mkPulumiPackage =
    {
      pkgs,
      nixpkgsPath ? pkgs.path,
    }:
    let
      mkSchema = pkgs.callPackage ./mk-schema.nix { };
      mkTerraformBridgeSchema = pkgs.callPackage ./mk-terraform-bridge-schema.nix { inherit mkSchema; };
      mkPulumiSchema = pkgs.callPackage ./mk-pulumi-schema.nix { inherit mkSchema; };
      langArgNames = pkgs.callPackage ./lang-arg-names.nix { };
      sdkBuilders = pkgs.callPackage ./sdks { };
      withSdks = pkgs.callPackage ./with-sdks.nix { inherit sdkBuilders langArgNames; };
      mkTerraformBridgeProvider = pkgs.callPackage ./mk-terraform-bridge-provider.nix {
        inherit nixpkgsPath mkTerraformBridgeSchema langArgNames withSdks;
      };
    in
    pkgs.callPackage ./mk-pulumi-package.nix {
      inherit
        mkTerraformBridgeProvider
        mkPulumiSchema
        ;
    };

  # The terraform-bridge base builder, with `<lang>Args` SDK layering (same
  # as mkPulumiPackage) but the tfgen schema-generation convention.
  mkTerraformBridgeProvider =
    {
      pkgs,
      nixpkgsPath ? pkgs.path,
    }:
    pkgs.callPackage ./mk-terraform-bridge-provider.nix {
      inherit nixpkgsPath;
      mkTerraformBridgeSchema = pkgs.callPackage ./mk-terraform-bridge-schema.nix {
        mkSchema = pkgs.callPackage ./mk-schema.nix { };
      };
      langArgNames = pkgs.callPackage ./lang-arg-names.nix { };
      withSdks = pkgs.callPackage ./with-sdks.nix {
        sdkBuilders = pkgs.callPackage ./sdks { };
        langArgNames = pkgs.callPackage ./lang-arg-names.nix { };
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

  # The generic base schema-extraction builder underlying both
  # mkTerraformBridgeSchema and mkPulumiSchema, taking an explicit
  # `schemaCommand` - the escape hatch for gen tools whose invocation
  # doesn't fit either wrapper's convention.
  mkSchema =
    { pkgs }:
    pkgs.callPackage ./mk-schema.nix { };

  # Attaches `<lang>Args`-driven SDK builds to any base derivation's
  # `passthru.sdks`, not just a terraform-bridge one.
  withSdks =
    { pkgs }:
    pkgs.callPackage ./with-sdks.nix {
      sdkBuilders = pkgs.callPackage ./sdks { };
      langArgNames = pkgs.callPackage ./lang-arg-names.nix { };
    };

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

  # Like withSdks, but for packages whose SDK source is generated on
  # demand from a schema.json (via mkGeneratedSdk) rather than fetched
  # from an upstream repo.
  withGeneratedSdks =
    { pkgs }:
    pkgs.callPackage ./with-generated-sdks.nix {
      sdkBuilders = pkgs.callPackage ./sdks { };
      mkGeneratedSdk = pkgs.callPackage ./mk-generated-sdk.nix { };
      langArgNames = pkgs.callPackage ./lang-arg-names.nix { };
    };

  # Builds a source-based, multi-language component provider package:
  # mkComponentSchema for passthru.schema, layered with per-language SDK
  # generation via withGeneratedSdks.
  mkComponentPackage =
    { pkgs }:
    pkgs.callPackage ./mk-component-package.nix {
      mkComponentSchema = pkgs.callPackage ./mk-component-schema.nix { };
      withGeneratedSdks = pkgs.callPackage ./with-generated-sdks.nix {
        sdkBuilders = pkgs.callPackage ./sdks { };
        mkGeneratedSdk = pkgs.callPackage ./mk-generated-sdk.nix { };
        langArgNames = pkgs.callPackage ./lang-arg-names.nix { };
      };
    };
}
