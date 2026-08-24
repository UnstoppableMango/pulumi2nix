# flake-parts module for declaring Pulumi provider, schema, and SDK builds.
#
#   imports = [ pulumi2nix.flakeModules.default ];
#   perSystem = { ... }: {
#     pulumi.terraformBridgeProviders.pulumi-random = { ... };
#   };
#
# Each declaration becomes `packages.<name>`, and its `passthru.schema` /
# `passthru.sdks.<lang>` are flattened out into `packages.<name>-schema` and
# `packages.<name>-sdk-<lang>`. Everything is mirrored into `checks`, which is
# what puts generated SDKs under `nix flake check`, alongside the check-only
# `checks.<name>-sdk-<lang>-generated` SDK drift checks.
{
  lib,
  flake-parts-lib,
  withSystem,
  ...
}:
let
  inherit (lib) mkOption types;

  sdkTypes = import ./sdks.nix { inherit lib; };
  treeOptions = import ./options.nix { inherit lib; };

  # Option tree -> the lib/default.nix builder it dispatches to.
  builders = {
    schemas = "mkSchema";
    nativeSchemas = "mkPulumiSchema";
    terraformBridgeSchemas = "mkTerraformBridgeSchema";
    componentSchemas = "mkComponentSchema";
    nativeProviders = "mkPulumiPackage";
    terraformBridgeProviders = "mkTerraformBridgeProvider";
    dynamicBridgeProviders = "mkDynamicBridgeProvider";
    componentPackages = "mkComponentPackage";
  };

  # Keys the module system or this module owns, never forwarded to a builder.
  # The per-SDK `exposePackage`/`exposeCheck` flags need no entry here: `sdks`
  # removes their enclosing `sdks.<lang>` submodules wholesale, and
  # `toLangArgs` strips them on the path that keeps them.
  internalKeys = [
    "sdks"
    "exposeSchema"
    "_module"
  ];

  stripNull = lib.filterAttrs (_: v: v != null);

  # Submodule configs carry `_module`; strip it wherever a submodule value is
  # forwarded as a plain attrset.
  stripModule = attrs: removeAttrs attrs [ "_module" ];

  cleanArgs =
    attrs:
    let
      base = stripNull (removeAttrs attrs internalKeys);
    in
    base
    // lib.optionalAttrs (base ? providerPlugins) {
      providerPlugins = map stripModule base.providerPlugins;
    }
    // lib.optionalAttrs (base ? schemaArgs) {
      schemaArgs = cleanArgs base.schemaArgs;
    }
    // lib.optionalAttrs (base ? sdkDrift) {
      sdkDrift = cleanSdkDrift base.sdkDrift;
    };

  # `sdkDrift.languages` is either a plain list of names or an attrset of
  # per-language submodules, so the nested cleanup only applies to the second
  # shape. Dropping nulls is the load-bearing half: the builder merges these
  # attrs *last*, so an unset `languagePlugin = null` would otherwise land on
  # top of the shared block's value instead of falling through to it.
  # `stripModule` is defensive: these attrsets are forwarded verbatim into
  # mkSdkDriftCheck's named formals, which have no ellipsis to absorb a stray
  # `_module`.
  cleanSdkDrift =
    sdkDrift:
    let
      base = stripNull (stripModule sdkDrift);
    in
    base
    // lib.optionalAttrs (base ? languages && !lib.isList base.languages) {
      languages = lib.mapAttrs (_: langCfg: stripNull (stripModule langCfg)) base.languages;
    };
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { config, pkgs, ... }:
    let
      cfg = config.pulumi;

      # Flat list of every declaration across every tree, so the names they all
      # claim can be checked for collisions in one place.
      declarations = lib.concatLists (
        lib.mapAttrsToList (
          tree: builder:
          lib.mapAttrsToList (name: value: {
            inherit tree builder name;
            cfg = value;
            drv = (cfg.lib.${builder} or (throw "pulumi2nix: lib has no builder '${builder}'")) (
              cleanArgs value // sdkTypes.toLangArgs (value.sdks or { })
            );
          }) cfg.${tree}
        ) builders
      );

      # `null` on a per-declaration or per-SDK flag means "inherit the tree-wide
      # default".
      resolve = value: fallback: if value == null then fallback else value;

      exposeSchema = d: resolve (d.cfg.exposeSchema or null) cfg.exposeSchemas;

      exposeSdk =
        d: lang: flag: fallback:
        let
          sdkCfg = (d.cfg.sdks or { }).${lang} or null;
        in
        resolve (if sdkCfg == null then null else sdkCfg.${flag}) fallback;

      schemaOf =
        d:
        lib.optionalAttrs (exposeSchema d && (d.drv.passthru or { }) ? schema) {
          "${d.name}-schema" = d.drv.passthru.schema;
        };

      sdksOf =
        d: flag: fallback:
        lib.concatMapAttrs (
          lang: sdk: lib.optionalAttrs (exposeSdk d lang flag fallback) { "${d.name}-sdk-${lang}" = sdk; }
        ) (d.drv.passthru.sdks or { });

      # Drift checks never become packages: an empty marker file is not
      # something anyone wants to `nix build`, and the whole point is that
      # `nix flake check` notices a stale SDK.
      driftChecksOf =
        d:
        lib.concatMapAttrs (lang: check: { "${d.name}-sdk-${lang}-generated" = check; }) (
          d.drv.passthru.sdkDriftChecks or { }
        );

      # Two declarations can collide either directly (same name in two trees) or
      # through flattening: a standalone `mkTerraformBridgeSchema` named
      # `foo-schema` claims the same output as provider `foo`'s `passthru.schema`.
      # Merging with `//` would silently drop one, so refuse instead.
      mergeUnique =
        what: sets:
        let
          names = lib.concatMap lib.attrNames sets;
          duplicates = lib.unique (lib.filter (name: lib.count (other: other == name) names > 1) names);
        in
        lib.throwIf (duplicates != [ ]) ''
          pulumi2nix: ${lib.concatStringsSep ", " duplicates} claimed more than once in `${what}`.

          Either two `pulumi.*` declarations share a name, or a declaration's name
          collides with another's flattened `<name>-schema` / `<name>-sdk-<lang>`
          output. Rename one, or suppress the flattened output with
          `exposeSchema = false` / `sdks.<lang>.exposePackage = false`.
        '' (lib.foldl' (acc: set: acc // set) { } sets);

      outputsFor =
        flag: fallback: d:
        { ${d.name} = d.drv; } // schemaOf d // sdksOf d flag fallback;

      packages = mergeUnique "packages" (map (d: { ${d.name} = d.drv; }) declarations);
    in
    {
      options.pulumi = treeOptions // {
        lib = mkOption {
          type = types.attrsOf types.raw;
          default = import ../lib { inherit pkgs; };
          defaultText = lib.literalExpression "pulumi2nix.lib { inherit pkgs; }";
          description = ''
            The instantiated pulumi2nix builder set. Also surfaced as the
            `pulumi2nix` module argument, so declarations can reach
            `pulumi2nix.pulumiLanguageDotnet` without extra plumbing.
          '';
        };

        exposeSchemas = mkOption {
          type = types.bool;
          default = true;
          description = "Emit `packages.<name>-schema` for declarations carrying `passthru.schema`.";
        };

        exposeSdks = mkOption {
          type = types.bool;
          default = true;
          description = "Default for every SDK's `exposePackage`.";
        };

        exposeSdkChecks = mkOption {
          type = types.bool;
          default = true;
          description = "Default for every SDK's `exposeCheck`.";
        };

        packages = mkOption {
          type = types.lazyAttrsOf types.package;
          readOnly = true;
          description = "The declared builds, by name. Excludes flattened schemas and SDKs.";
        };

        overlayAttrs = mkOption {
          type = types.lazyAttrsOf types.package;
          readOnly = true;
          description = "What `overlays.pulumiPackages` contributes for this system.";
        };
      };

      config = {
        _module.args.pulumi2nix = cfg.lib;

        pulumi.packages = packages;
        pulumi.overlayAttrs = packages;

        packages = mergeUnique "packages" (map (outputsFor "exposePackage" cfg.exposeSdks) declarations);

        checks = mergeUnique "checks" (
          map (d: outputsFor "exposeCheck" cfg.exposeSdkChecks d // driftChecksOf d) declarations
        );
      };
    }
  );

  # Reads the system off `prev`, not `final`: `final.stdenv` is unbuilt while
  # the overlay list is being applied, so touching it here recurses.
  config.flake.overlays.pulumiPackages =
    _final: prev:
    withSystem prev.stdenv.hostPlatform.system ({ config, ... }: config.pulumi.overlayAttrs);
}
