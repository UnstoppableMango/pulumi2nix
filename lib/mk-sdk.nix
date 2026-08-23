# Looks up a per-language SDK builder in the `lib/sdks` registry and applies it,
# turning an unregistered language into a readable error rather than an
# attribute-missing one. Shared by with-sdks.nix and with-generated-sdks.nix;
# `caller` only names the file the bad `<lang>Args` was passed to.
{ lib, sdkBuilders }:
caller: lang: langArgs:
(sdkBuilders.${lang}
  or (throw "${caller}: no SDK builder registered for language '${lang}' (available: ${lib.concatStringsSep ", " (lib.attrNames sdkBuilders)})")
)
  langArgs
