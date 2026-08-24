{
  lib,
  attachSdks,
  mkSdk,
  mkGeneratedSdk,
  mkGeneratedGoSdk,
  langArgNames,
}:
{
  base,
  schema,
  pname,
  version,
  meta ? { },
  ...
}@args:
let
  argNames = langArgNames args;

  goOnlyArgs = [
    "importBasePath"
    "goMod"
    "goSum"
  ];

  missingGoArgs = lib.optionals (args ? goArgs) (
    lib.filter (name: !(args.goArgs ? ${name})) goOnlyArgs
  );

  mkSrc =
    lang: langArgs:
    let
      generated = mkGeneratedSdk (
        {
          inherit
            schema
            pname
            version
            meta
            lang
            ;
          inherit (langArgs) languagePlugin;
        }
        // lib.optionalAttrs (lang == "go") {
          schemaOverrides.language.go.importBasePath = langArgs.importBasePath;
        }
      );
    in
    if lang == "go" then
      mkGeneratedGoSdk {
        inherit pname version meta;
        src = generated;
        inherit (langArgs) goMod goSum;
      }
    else
      generated;

  extraSdks = lib.listToAttrs (
    map (
      argName:
      let
        lang = lib.removeSuffix "Args" argName;
        langArgs = args.${argName};
      in
      {
        name = lang;
        value = mkSdk "lib/with-generated-sdks.nix" lang (
          {
            inherit pname meta version;
            src = mkSrc lang langArgs;
          }
          // (removeAttrs langArgs ([ "languagePlugin" ] ++ goOnlyArgs))
        );
      }
    ) argNames
  );
in
lib.throwIf (args ? pythonArgs)
  ''
    withGeneratedSdks: `pythonArgs` isn't supported for source-based component
    providers. Unlike mkPulumiPackage/mkTerraformBridgeProvider, there's no
    upstream mkPythonPackage to delegate to here - only the languages
    registered in lib/sdks (nodejs, yarnNodejs, go, dotnet) are available.
  ''
  (
    lib.throwIf (missingGoArgs != [ ]) ''
      withGeneratedSdks: `goArgs` is missing ${lib.concatStringsSep ", " missingGoArgs}.
      `pulumi package gen-sdk --language go` emits only .go sources, so a generated go
      SDK additionally needs `importBasePath` (the schema's `language.go.importBasePath`,
      without which codegen writes self-imports that don't match the directories it just
      created) plus a `go.mod`/`go.sum` pair, the same way `nodejsArgs` needs a
      `package-lock.json`. See the README for how to regenerate them.
    '' (attachSdks base extraSdks)
  )
