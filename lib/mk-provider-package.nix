# Composes the artifact builders into a complete provider package:
#
#   mkGenTool -> mkSchema -> mkProviderPlugin -> withSdks -> mkSdkDriftCheck*
#
# Native and bridged providers are the same composition with a different schema
# convention, so both are presets over this recipe rather than one calling the
# other. `schemaCommand` is the gen tool's own invocation, and `embedSchema`
# says whether the plugin binary carries the schema (a bridged provider embeds
# it; a `pulumi-go-provider` native one serves it from Go structs).
#
# The result is the plugin binary, carrying `passthru.schema`,
# `passthru.genTool`, `passthru.sdks.<lang>` and `passthru.sdkDriftChecks`.
{
  lib,
  fetchProviderSource,
  langArgNames,
  mkGenTool,
  mkProviderPlugin,
  mkSchema,
  mkSdkDriftCheck,
  mkSdkSource,
  withSdks,
}:
{
  repo,
  version,
  vendorHash,
  cmdGen,
  cmdRes,
  schemaCommand,
  embedSchema ? false,
  ...
}@args:
let
  caller = "mk-provider-package.nix";

  src = args.src or (fetchProviderSource caller args);
  meta = args.meta or { };
  env = args.env or { };
  extraLdflags = args.extraLdflags or [ ];
  pname = args.pname or repo;
  sdkDrift = args.sdkDrift or { };

  langNames = langArgNames args;

  controlArgs = [
    "schemaCommand"
    "embedSchema"
    "sdkDrift"
    "pname"
    "sdks"
  ];

  genTool = mkGenTool {
    inherit
      src
      version
      vendorHash
      cmdGen
      extraLdflags
      env
      meta
      ;
  };

  schema = mkSchema {
    inherit
      src
      repo
      version
      schemaCommand
      genTool
      meta
      ;
  };

  plugin = mkProviderPlugin (
    removeAttrs args (langNames ++ controlArgs)
    // {
      inherit
        src
        version
        cmdRes
        pname
        ;

      schema = if embedSchema then schema else null;
    }
  );

  # The name a python SDK distributes under follows the plugin name rather than
  # the repo's: `pulumi-resource-random` gives `pulumi-random`, which is what
  # tfgen writes into the SDK whatever the repo is called.
  distName = "pulumi-" + lib.removePrefix "pulumi-resource-" cmdRes;

  langArgs = lib.genAttrs langNames (
    name: if name == "pythonArgs" then { inherit distName; } // args.${name} else args.${name}
  );

  layered = withSdks (
    langArgs
    // {
      base = plugin;
      inherit
        src
        schema
        version
        meta
        pname
        ;
    }
  );

  declaredLangs = sdkDrift.languages or [ ];
  driftLangs =
    if lib.isList declaredLangs then lib.genAttrs declaredLangs (_: { }) else declaredLangs;

  driftDefaults = removeAttrs sdkDrift [ "languages" ];

  sdkDriftChecks = lib.mapAttrs (
    lang: langDrift:
    let
      settings = driftDefaults // langDrift;
    in
    mkSdkDriftCheck (
      removeAttrs settings [
        "languagePlugin"
        "sdkPath"
      ]
      // lib.optionalAttrs (settings ? sdkPath) { committedPath = settings.sdkPath; }
      // {
        inherit
          lang
          pname
          version
          meta
          ;

        regenerateCommand = "`${cmdGen} ${lang} --out sdk/${lang}` (usually via the repo's `make generate`)";

        committed = mkSdkSource {
          inherit
            lang
            pname
            version
            meta
            src
            ;
        };

        against = mkSdkSource {
          inherit
            lang
            pname
            version
            meta
            src
            genTool
            ;

          languagePlugin = settings.languagePlugin or null;
        };
      }
    )
  ) driftLangs;
in
layered.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    inherit schema genTool sdkDriftChecks;
  };
})
