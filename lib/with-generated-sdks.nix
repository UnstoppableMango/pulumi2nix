# Like with-sdks.nix, but for packages whose per-language SDK source is
# generated on demand from a schema.json via mkGeneratedSdk (component
# providers) instead of fetched from an upstream repo. Each `<lang>Args`
# block carries a `languagePlugin` consumed here, stripped before forwarding
# the rest to `sdkBuilders.${lang}`.
{
  lib,
  sdkBuilders,
  mkGeneratedSdk,
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
assert
  !(args ? pythonArgs)
  || throw ''
    withGeneratedSdks: `pythonArgs` isn't supported for source-based component
    providers. Unlike mkPulumiPackage/mkTerraformBridgeProvider, there's no
    upstream mkPythonPackage to delegate to here - only the languages
    registered in lib/sdks (nodejs, yarnNodejs, go, dotnet) are available.
  '';
let
  argNames = langArgNames args;

  mkSdk =
    lang: langArgs:
    (sdkBuilders.${lang}
      or (throw "lib/with-generated-sdks.nix: no SDK builder registered for language '${lang}' (available: ${lib.concatStringsSep ", " (builtins.attrNames sdkBuilders)})")
    )
      langArgs;

  extraSdks = lib.listToAttrs (
    map (
      argName:
      let
        lang = lib.removeSuffix "Args" argName;
        langArgs = args.${argName};
        generatedSrc = mkGeneratedSdk {
          inherit
            schema
            pname
            version
            meta
            lang
            ;
          inherit (langArgs) languagePlugin;
        };
      in
      {
        name = lang;
        value = mkSdk lang (
          {
            inherit pname meta version;
            src = generatedSrc;
          }
          // (removeAttrs langArgs [ "languagePlugin" ])
        );
      }
    ) argNames
  );
in
if extraSdks == { } then
  base
else
  base.overrideAttrs (old: {
    passthru = old.passthru // {
      sdks = (old.passthru.sdks or { }) // extraSdks;
    };
  })
