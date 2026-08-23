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

  # Callers that resolve a `src` themselves (mkTerraformBridgeProvider does)
  # pass it through so the <lang>Args builders share it. Standalone callers
  # wrapping a base derivation built elsewhere get a fallback fetch instead;
  # its inputs match the usual base-builder fetch, so it dedupes at the store
  # level rather than fetching twice.
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
            # Lang-qualified so the provider and each of its SDKs get distinct
            # derivation names. An unqualified `repo` makes every store path,
            # build log line and `nix flake check` entry read the same. This
            # matches the flattened `packages.<name>-sdk-<lang>` output the
            # flake module already produces. A per-SDK `pname` still wins,
            # since `args.${argName}` merges last.
            pname = "${args.repo}-sdk-${lang}";

            # Each SDK gets only the part of the shared tree it builds from, so
            # editing a file no SDK reads stops rebuilding all of them. See
            # lib/narrow-sdk-src.nix for what that covers and how to opt out.
            src = narrowSdkSrc.narrow lang src langArgs;
          }
          // removeAttrs langArgs narrowSdkSrc.optionNames
        );
      }
    ) argNames
  );
in
attachSdks base extraSdks
