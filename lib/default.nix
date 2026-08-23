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

    # Resolves the directory name unpackPhase leaves behind for a given `src`,
    # so `sourceRoot` works for caller-supplied sources as well as fetcher output.
    srcName = callPackage ./src-name.nix { };

    # The default `owner`/`repo`/`rev`/`hash` fetch every repo-based builder
    # falls back to when the caller supplies no `src`.
    fetchProviderSource = callPackage ./fetch-provider-source.nix { };

    # Cuts a shared provider `src` down to just the subtree one language's SDK
    # builds from, so an unrelated file change stops rebuilding every SDK.
    narrowSdkSrc = callPackage ./narrow-sdk-src.nix { };

    # Registry of per-language SDK builders (lang name -> builder function).
    # Given the augmented callPackage so the builders can reach `srcName`.
    sdkBuilders = callPackage ./sdks { inherit callPackage; };

    # Applies one of those builders by language name, with a readable error for
    # a language that isn't registered.
    mkSdk = callPackage ./mk-sdk.nix { };

    # Attaches `<lang>Args`-driven SDK builds to any base derivation's `passthru.sdks`.
    withSdks = callPackage ./with-sdks.nix { };

    # Fails when a provider's committed `sdk/<lang>` no longer matches what its
    # gen tool emits, which the SDK builds themselves cannot notice.
    mkSdkDriftCheck = callPackage ./mk-sdk-drift-check.nix { };

    # The terraform-bridge base builder, using the tfgen schema-generation convention.
    mkTerraformBridgeProvider = callPackage ./mk-terraform-bridge-provider.nix { };

    # Builds the generic, dynamically-bridged `pulumi-resource-terraform-provider`
    # binary, which bridges any Terraform provider at runtime rather than being
    # generated ahead-of-time for one specific upstream provider.
    mkDynamicBridgeProvider = callPackage ./mk-dynamic-bridge-provider.nix { };

    # Builds nixpkgs-style Go/Terraform-bridge Pulumi provider packages, layered with
    # composable per-language SDK builders via withSdks.
    mkPulumiPackage = callPackage ./mk-pulumi-package.nix { };

    # nixpkgs has no `pulumi-language-dotnet` builder, so this is a pinned build
    # for use as a `pulumi package gen-sdk --language dotnet` plugin.
    pulumiLanguageDotnet = callPackage ./pulumi-language-dotnet.nix { };

    # Generates a language SDK's source tree on demand from a schema.json, for
    # packages that don't ship one upstream (e.g. component providers).
    mkGeneratedSdk = callPackage ./mk-generated-sdk.nix { };

    # Attaches a caller-supplied `go.mod`/`go.sum` to a generated go SDK's source tree,
    # which `pulumi package gen-sdk` never emits.
    mkGeneratedGoSdk = callPackage ./mk-generated-go-sdk.nix { };

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
