{ pkgs }:
{
  # Builds nixpkgs-style Go/Terraform-bridge Pulumi provider packages, layered with
  # composable per-language SDK builders via withSdks.
  mkPulumiPackage =
    let
      mkSchema = pkgs.callPackage ./mk-schema.nix { };
      mkTerraformBridgeSchema = pkgs.callPackage ./mk-terraform-bridge-schema.nix { inherit mkSchema; };
      mkPulumiSchema = pkgs.callPackage ./mk-pulumi-schema.nix { inherit mkSchema; };
      langArgNames = pkgs.callPackage ./lang-arg-names.nix { };
      sdkBuilders = pkgs.callPackage ./sdks { };
      withSdks = pkgs.callPackage ./with-sdks.nix { inherit sdkBuilders langArgNames; };
      mkTerraformBridgeProvider = pkgs.callPackage ./mk-terraform-bridge-provider.nix {
        inherit
          mkTerraformBridgeSchema
          langArgNames
          withSdks
          ;
      };
    in
    pkgs.callPackage ./mk-pulumi-package.nix {
      inherit
        mkTerraformBridgeProvider
        mkPulumiSchema
        ;
    };

  # The terraform-bridge base builder, using the tfgen schema-generation convention.
  mkTerraformBridgeProvider = pkgs.callPackage ./mk-terraform-bridge-provider.nix {
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
  mkTerraformBridgeSchema = pkgs.callPackage ./mk-terraform-bridge-schema.nix {
    mkSchema = pkgs.callPackage ./mk-schema.nix { };
  };

  # Same, but for native providers whose gen tool takes an explicit output
  # path and version flag instead of a "schema" subcommand.
  mkPulumiSchema = pkgs.callPackage ./mk-pulumi-schema.nix {
    mkSchema = pkgs.callPackage ./mk-schema.nix { };
  };

  # The generic base schema-extraction builder underlying both schema wrappers,
  # taking an explicit `schemaCommand` as an escape hatch for gen tools that don't
  # fit either convention.
  mkSchema = pkgs.callPackage ./mk-schema.nix { };

  # Attaches `<lang>Args`-driven SDK builds to any base derivation's `passthru.sdks`.
  withSdks = pkgs.callPackage ./with-sdks.nix {
    sdkBuilders = pkgs.callPackage ./sdks { };
    langArgNames = pkgs.callPackage ./lang-arg-names.nix { };
  };

  # Registry of per-language SDK builders (lang name -> builder function).
  sdkBuilders = pkgs.callPackage ./sdks { };

  # nixpkgs has no `pulumi-language-dotnet` builder, so this is a pinned build
  # for use as a `pulumi package gen-sdk --language dotnet` plugin.
  pulumiLanguageDotnet = pkgs.callPackage ./pulumi-language-dotnet.nix { };

  # Generates a language SDK's source tree on demand from a schema.json, for
  # packages that don't ship one upstream (e.g. component providers).
  mkGeneratedSdk = pkgs.callPackage ./mk-generated-sdk.nix { };

  # Extracts schema.json from a source-based, multi-language component provider
  # via `pulumi package get-schema`, rather than building a separate gen tool.
  mkComponentSchema = pkgs.callPackage ./mk-component-schema.nix { };

  # Like withSdks, but for packages whose SDK source is generated on demand
  # from a schema.json rather than fetched from an upstream repo.
  withGeneratedSdks = pkgs.callPackage ./with-generated-sdks.nix {
    sdkBuilders = pkgs.callPackage ./sdks { };
    mkGeneratedSdk = pkgs.callPackage ./mk-generated-sdk.nix { };
    langArgNames = pkgs.callPackage ./lang-arg-names.nix { };
  };

  # Builds a source-based, multi-language component provider package, layered
  # with per-language SDK generation via withGeneratedSdks.
  mkComponentPackage = pkgs.callPackage ./mk-component-package.nix {
    mkComponentSchema = pkgs.callPackage ./mk-component-schema.nix { };
    withGeneratedSdks = pkgs.callPackage ./with-generated-sdks.nix {
      sdkBuilders = pkgs.callPackage ./sdks { };
      mkGeneratedSdk = pkgs.callPackage ./mk-generated-sdk.nix { };
      langArgNames = pkgs.callPackage ./lang-arg-names.nix { };
    };
  };
}
