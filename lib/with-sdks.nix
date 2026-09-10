# Attaches `<lang>Args`-driven SDK builds to a base derivation's
# `passthru.sdks`.
#
# One layerer for both SDK source routes: each `<lang>Args` block picks its
# producer with `generate`, and `mkSdkSource` resolves that to a committed
# `sdk/<lang>` or to codegen against `schema`. Per-language, so one provider can
# commit some SDKs and generate others.
#
# It *overrides* onto whatever the derivation beneath already carries rather
# than replacing it, so a caller can layer twice. An empty set returns `base`
# untouched, so a provider that declares no SDKs pays no `overrideAttrs`.
{
  lib,
  fetchProviderSource,
  langArgNames,
  mkSdk,
  mkSdkSource,
}:
{
  base,
  pname,
  version,
  meta ? { },
  src ? null,
  schema ? null,
  ...
}@args:
let
  caller = "lib/with-sdks.nix";

  argNames = langArgNames args;

  resolvedSrc = if src != null then src else fetchProviderSource caller args;

  # Arguments consumed by mkSdkSource, which the language builder never sees.
  sourceOnlyArgs = [
    "generate"
    "languagePlugin"
    "narrowSrc"
    "srcPaths"
    "schemaOverrides"
    "importBasePath"
    "goMod"
    "goSum"
  ];

  goOnlyArgs = [
    "importBasePath"
    "goMod"
    "goSum"
  ];

  sdkFor =
    argName:
    let
      lang = lib.removeSuffix "Args" argName;
      langArgs = args.${argName};
      generate = langArgs.generate or false;

      missingGoArgs = lib.optionals (lang == "go" && generate) (
        lib.filter (name: !(langArgs ? ${name})) goOnlyArgs
      );

      requireSchema = lib.throwIf (generate && schema == null) ''
        ${caller}: ${lang} sets `generate` but no `schema` reached this call, so
        there is nothing to codegen from. Provider and component recipes pass their
        own schema derivation; a direct caller has to supply one.
      '';

      requireGoArgs = lib.throwIf (missingGoArgs != [ ]) ''
        ${caller}: `${argName}` is missing ${lib.concatStringsSep ", " missingGoArgs}.
        `pulumi package gen-sdk --language go` emits only .go sources, so a generated go
        SDK additionally needs `importBasePath` (the schema's `language.go.importBasePath`,
        without which codegen writes self-imports that don't match the directories it just
        created) plus a `go.mod`/`go.sum` pair, the same way `nodejsArgs` needs a
        `package-lock.json`. See the README for how to regenerate them.
      '';

      generatedSource = {
        inherit schema;
        languagePlugin = langArgs.languagePlugin or null;
        goMod = langArgs.goMod or null;
        goSum = langArgs.goSum or null;

        schemaOverrides =
          langArgs.schemaOverrides or (lib.optionalAttrs (lang == "go") {
            language.go.importBasePath = langArgs.importBasePath;
          });
      };

      committedSource = {
        src = resolvedSrc;
        narrowSrc = langArgs.narrowSrc or true;
      }
      // lib.optionalAttrs (langArgs ? srcPaths) { inherit (langArgs) srcPaths; };

      source = mkSdkSource (
        {
          inherit
            lang
            pname
            version
            meta
            ;
        }
        // (if generate then generatedSource else committedSource)
      );
    in
    requireSchema (
      requireGoArgs (
        mkSdk caller lang (
          {
            inherit version meta;
            pname = "${pname}-sdk-${lang}";
            src = source;
          }
          // removeAttrs langArgs sourceOnlyArgs
        )
      )
    );

  extraSdks = lib.listToAttrs (
    map (argName: {
      name = lib.removeSuffix "Args" argName;
      value = sdkFor argName;
    }) argNames
  );
in
if extraSdks == { } then
  base
else
  base.overrideAttrs (old: {
    passthru = (old.passthru or { }) // {
      sdks = (old.passthru.sdks or { }) // extraSdks;
    };
  })
