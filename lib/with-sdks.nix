{
  lib,
  attachSdks,
  fetchProviderSource,
  mkSdk,
  langArgNames,
  narrowSdkSrc,
}:
{
  base,
  ...
}@args:
let
  argNames = langArgNames args;

  src = args.src or (fetchProviderSource "lib/with-sdks.nix" args);

  extraSdks = lib.listToAttrs (
    map (
      argName:
      let
        lang = lib.removeSuffix "Args" argName;
        langArgs = args.${argName};
      in
      {
        name = lang;
        value = mkSdk "lib/with-sdks.nix" lang (
          {
            inherit (args) version;
            meta = args.meta or { };
            pname = "${args.repo}-sdk-${lang}";

            src = narrowSdkSrc.narrow lang src langArgs;
          }
          // removeAttrs langArgs narrowSdkSrc.optionNames
        );
      }
    ) argNames
  );
in
attachSdks base extraSdks
