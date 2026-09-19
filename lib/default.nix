{ pkgs }:
let
  callPackage = pkgs.lib.callPackageWith (pkgs // self);

  # Every builder as an uninstantiated path. `mkPackageSet` needs these rather
  # than the bound functions below: a builder instantiated here closes over
  # `pkgs`, so a member calling it would reach `pulumi` from the outer `pkgs`
  # and the set's pin would not apply. The set re-instantiates each one in its
  # own scope.
  builderPaths = {
    ## Artifact builders. One Pulumi artifact each, no composition.

    # The provider repo's `cmd/pulumi-{tf,}gen-<name>` schema generation tool.
    mkGenTool = ./mk-gen-tool.nix;

    # `schema.json`, by running that gen tool. `schemaCommand` is the one thing
    # that differs between conventions.
    mkSchema = ./mk-schema.nix;

    # `schema.json` for a source-based, multi-language component provider, via
    # `pulumi package get-schema` rather than a compiled gen tool.
    mkComponentSchema = ./mk-component-schema.nix;

    # The `pulumi-resource-<name>` plugin binary, native or bridged.
    mkProviderPlugin = ./mk-provider-plugin.nix;

    # A component provider's plugin: its source tree plus `PulumiPlugin.yaml`.
    mkComponentPlugin = ./mk-component-plugin.nix;

    # The generic `pulumi-resource-terraform-provider` binary, which bridges any
    # Terraform provider at runtime instead of being generated ahead of time.
    mkDynamicPlugin = ./mk-dynamic-plugin.nix;

    # One language's SDK source tree, from a committed `sdk/<lang>`, from
    # `gen-sdk` against a schema, or from the gen tool emitting it directly.
    mkSdkSource = ./mk-sdk-source.nix;

    # One packaged SDK, by language, from an SDK source tree.
    mkSdk = ./mk-sdk.nix;

    ## Package recipes. Composition over the builders above.

    # A native provider: gen tool, schema, plugin binary, SDKs.
    mkPulumiPackage = ./mk-pulumi-package.nix;

    # The same for a provider bridged from Terraform ahead of time.
    mkTerraformBridgeProvider = ./mk-terraform-bridge-provider.nix;

    # What both presets sit on: the shared provider composition.
    mkProviderPackage = ./mk-provider-package.nix;

    # A component provider: schema, plugin tree, generated SDKs.
    mkComponentPackage = ./mk-component-package.nix;

    # The dynamic bridge has no schema and no SDKs, so its recipe is its builder.
    mkDynamicBridgeProvider = ./mk-dynamic-plugin.nix;

    ## Package sets. A versioned group of the above, built against shared pins.

    # A plugin cache tree, and optionally a pinned CLI, over a selection of a
    # set's plugins. The only derivation that varies per selection, and it is
    # symlinks.
    mkPulumiEnv = ./mk-pulumi-env.nix;

    ## Utilities.

    # Schema-command presets over mkSchema, for the two gen tool conventions.
    mkTerraformBridgeSchema = ./mk-terraform-bridge-schema.nix;
    mkPulumiSchema = ./mk-pulumi-schema.nix;

    # Attaches `<lang>Args`-driven SDK builds to any base derivation's
    # `passthru.sdks`, resolving each language's source through mkSdkSource.
    withSdks = ./with-sdks.nix;

    # Fails when a provider's committed `sdk/<lang>` doesn't match what the
    # provider generates. A diff of two mkSdkSource trees; builds nothing itself.
    mkSdkDriftCheck = ./mk-sdk-drift-check.nix;

    # Registry of per-language SDK builders (lang name -> builder function).
    # Needs a callPackage that resolves `srcName`, which a scope's own
    # callPackage does and `pkgs.callPackage` does not, so `self` below
    # instantiates it explicitly rather than through `callPackage path { }`.
    sdkBuilders = ./sdks;

    # Picks out the caller args that select per-language SDK builds (e.g.
    # `nodejsArgs`, `goArgs`).
    langArgNames = ./lang-arg-names.nix;

    # Resolves the directory name unpackPhase leaves behind for a given `src`,
    # so `sourceRoot` works for caller-supplied sources as well as fetcher output.
    srcName = ./src-name.nix;

    # The default `owner`/`repo`/`rev`/`hash` fetch every repo-based builder
    # falls back to when the caller supplies no `src`.
    fetchProviderSource = ./fetch-provider-source.nix;

    # Cuts a shared provider `src` down to just the subtree one language's SDK
    # builds from, so an unrelated file change stops rebuilding every SDK.
    narrowSdkSrc = ./narrow-sdk-src.nix;

    # Normalizes a plugin package to the `{ name, version, plugin, dir }` shape
    # Pulumi's plugin cache is keyed by.
    pluginRef = ./plugin-ref.nix;

    # The shell snippet that copies a list of plugins into a writable
    # `$PULUMI_HOME/plugins`, so a build can resolve them offline.
    seedPlugins = ./seed-plugins.nix;

    # nixpkgs has no `pulumi-language-dotnet` builder, so this is a pinned build
    # for use as a `pulumi package gen-sdk --language dotnet` plugin.
    pulumiLanguageDotnet = ./pulumi-language-dotnet.nix;

    ## Deprecated aliases, kept so existing callers keep working.

    # Use mkSdkSource with a `schema`.
    mkGeneratedSdk = ./mk-generated-sdk.nix;

    # Use mkSdkSource's `goMod`/`goSum`, which complete a generated go tree in
    # the same derivation.
    mkGeneratedGoSdk = ./mk-generated-go-sdk.nix;

    # Use withSdks, which now covers both SDK source routes.
    withGeneratedSdks = ./with-generated-sdks.nix;
  };

  # `builtins.mapAttrs` rather than `lib.mapAttrs`: `pkgs // self` needs only
  # `self`'s attribute names, and reaching for `pkgs.lib` to produce them would
  # make that circular under an overlay that itself pulls from here.
  self = builtins.mapAttrs (_: path: callPackage path { }) builderPaths // {
    # A named, versioned scope of packages. What a channel is: `.extend` derives
    # one set from another, and unchanged members keep their store paths.
    mkPackageSet = callPackage ./mk-package-set.nix { builders = builderPaths; };

    # The augmented callPackage, so the per-language builders reach `srcName`.
    sdkBuilders = callPackage ./sdks { inherit callPackage; };
  };
in
self
