{ lib, sdkBuilders }:
caller: lang: langArgs:
(sdkBuilders.${lang}
  or (throw "${caller}: no SDK builder registered for language '${lang}' (available: ${lib.concatStringsSep ", " (lib.attrNames sdkBuilders)})")
)
  langArgs
