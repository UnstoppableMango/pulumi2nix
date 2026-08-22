{ pkgs }:
let
  callPackage = pkgs.lib.callPackageWith (pkgs // self);

  self = {
    # The generic base schema-extraction builder underlying both schema wrappers,
    # taking an explicit `schemaCommand` as an escape hatch for gen tools that don't
    # fit either convention.
    mkSchema = callPackage ./mk-schema.nix { };

    # Builds only a terraform-bridge provider's generated schema.json, without
    # the resource provider binary or any SDKs.
    mkTerraformBridgeSchema = callPackage ./mk-terraform-bridge-schema.nix { };

    # Same, but for native providers whose gen tool takes an explicit output
    # path and version flag instead of a "schema" subcommand.
    mkPulumiSchema = callPackage ./mk-pulumi-schema.nix { };

    # Picks out the caller args that select per-language SDK builds (e.g.
    # `nodejsArgs`, `goArgs`), shared by withSdks and withGeneratedSdks.
    langArgNames = callPackage ./lang-arg-names.nix { };

    # Registry of per-language SDK builders (lang name -> builder function).
    sdkBuilders = callPackage ./sdks { };

    # Attaches `<lang>Args`-driven SDK builds to any base derivation's `passthru.sdks`.
    withSdks = callPackage ./with-sdks.nix { };

    # The terraform-bridge base builder, using the tfgen schema-generation convention.
    mkTerraformBridgeProvider = callPackage ./mk-terraform-bridge-provider.nix { };

    # Builds nixpkgs-style Go/Terraform-bridge Pulumi provider packages, layered with
    # composable per-language SDK builders via withSdks.
    mkPulumiPackage = callPackage ./mk-pulumi-package.nix { };

    # nixpkgs has no `pulumi-language-dotnet` builder, so this is a pinned build
    # for use as a `pulumi package gen-sdk --language dotnet` plugin.
    pulumiLanguageDotnet = callPackage ./pulumi-language-dotnet.nix { };

    # Generates a language SDK's source tree on demand from a schema.json, for
    # packages that don't ship one upstream (e.g. component providers).
    mkGeneratedSdk = callPackage ./mk-generated-sdk.nix { };

    # Extracts schema.json from a source-based, multi-language component provider
    # via `pulumi package get-schema`, rather than building a separate gen tool.
    mkComponentSchema = callPackage ./mk-component-schema.nix { };

    # Like withSdks, but for packages whose SDK source is generated on demand
    # from a schema.json rather than fetched from an upstream repo.
    withGeneratedSdks = callPackage ./with-generated-sdks.nix { };

    # Builds a source-based, multi-language component provider package, layered
    # with per-language SDK generation via withGeneratedSdks.
    mkComponentPackage = callPackage ./mk-component-package.nix { };
  };
in
self
