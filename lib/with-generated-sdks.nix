# Like with-sdks.nix, but for packages whose per-language SDK source isn't
# fetched from an upstream repo - it's generated on demand from a
# schema.json via mkGeneratedSdk (component providers, see
# mk-component-package.nix). Each `<lang>Args` block carries a
# `languagePlugin` (consumed here, by mkGeneratedSdk) alongside that
# language's own sdkBuilders packaging args (e.g. `lockFile`/`npmDepsHash`
# for nodejs) - stripped before forwarding the rest to `sdkBuilders.${lang}`,
# same as with-sdks.nix does for its own per-language args.
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
  meta,
  ...
}@args:
let
  argNames = langArgNames args;

  mkSdk =
    lang: langArgs:
    (sdkBuilders.${lang}
      or (throw "lib/with-generated-sdks.nix: no SDK builder registered for language '${lang}'")
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
  base
  // {
    passthru = base.passthru // {
      sdks = (base.passthru.sdks or { }) // extraSdks;
    };
  }
