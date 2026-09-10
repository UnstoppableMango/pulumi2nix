{ pkgs }:
let
  callPackage = pkgs.lib.callPackageWith (pkgs // self);

  self = {
    ## Artifact builders. One Pulumi artifact each, no composition.

    # The provider repo's `cmd/pulumi-{tf,}gen-<name>` schema generation tool.
    mkGenTool = callPackage ./mk-gen-tool.nix { };

    # `schema.json`, by running that gen tool. `schemaCommand` is the one thing
    # that differs between conventions.
    mkSchema = callPackage ./mk-schema.nix { };

    # `schema.json` for a source-based, multi-language component provider, via
    # `pulumi package get-schema` rather than a compiled gen tool.
    mkComponentSchema = callPackage ./mk-component-schema.nix { };

    # The `pulumi-resource-<name>` plugin binary, native or bridged.
    mkProviderPlugin = callPackage ./mk-provider-plugin.nix { };

    # A component provider's plugin: its source tree plus `PulumiPlugin.yaml`.
    mkComponentPlugin = callPackage ./mk-component-plugin.nix { };

    # The generic `pulumi-resource-terraform-provider` binary, which bridges any
    # Terraform provider at runtime instead of being generated ahead of time.
    mkDynamicPlugin = callPackage ./mk-dynamic-plugin.nix { };

    # One language's SDK source tree, from a committed `sdk/<lang>`, from
    # `gen-sdk` against a schema, or from the gen tool emitting it directly.
    mkSdkSource = callPackage ./mk-sdk-source.nix { };

    # One packaged SDK, by language, from an SDK source tree.
    mkSdk = callPackage ./mk-sdk.nix { };

    ## Package recipes. Composition over the builders above.

    # A native provider: gen tool, schema, plugin binary, SDKs.
    mkPulumiPackage = callPackage ./mk-pulumi-package.nix { };

    # The same for a provider bridged from Terraform ahead of time.
    mkTerraformBridgeProvider = callPackage ./mk-terraform-bridge-provider.nix { };

    # What both presets sit on: the shared provider composition.
    mkProviderPackage = callPackage ./mk-provider-package.nix { };

    # A component provider: schema, plugin tree, generated SDKs.
    mkComponentPackage = callPackage ./mk-component-package.nix { };

    # The dynamic bridge has no schema and no SDKs, so its recipe is its builder.
    mkDynamicBridgeProvider = self.mkDynamicPlugin;

    ## Utilities.

    # Schema-command presets over mkSchema, for the two gen tool conventions.
    mkTerraformBridgeSchema = callPackage ./mk-terraform-bridge-schema.nix { };
    mkPulumiSchema = callPackage ./mk-pulumi-schema.nix { };

    # Attaches `<lang>Args`-driven SDK builds to any base derivation's
    # `passthru.sdks`, resolving each language's source through mkSdkSource.
    withSdks = callPackage ./with-sdks.nix { };

    # Fails when a provider's committed `sdk/<lang>` doesn't match what the
    # provider generates. A diff of two mkSdkSource trees; builds nothing itself.
    mkSdkDriftCheck = callPackage ./mk-sdk-drift-check.nix { };

    # Registry of per-language SDK builders (lang name -> builder function).
    # Given the augmented callPackage so the builders can reach `srcName`.
    sdkBuilders = callPackage ./sdks { inherit callPackage; };

    # Picks out the caller args that select per-language SDK builds (e.g.
    # `nodejsArgs`, `goArgs`).
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

    # nixpkgs has no `pulumi-language-dotnet` builder, so this is a pinned build
    # for use as a `pulumi package gen-sdk --language dotnet` plugin.
    pulumiLanguageDotnet = callPackage ./pulumi-language-dotnet.nix { };

    ## Deprecated aliases, kept so existing callers keep working.

    # Use mkSdkSource with a `schema`.
    mkGeneratedSdk = callPackage ./mk-generated-sdk.nix { };

    # Use mkSdkSource's `goMod`/`goSum`, which complete a generated go tree in
    # the same derivation.
    mkGeneratedGoSdk = callPackage ./mk-generated-go-sdk.nix { };

    # Use withSdks, which now covers both SDK source routes.
    withGeneratedSdks = callPackage ./with-generated-sdks.nix { };
  };
in
self
