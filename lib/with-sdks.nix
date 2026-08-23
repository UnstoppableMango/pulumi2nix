{
  lib,
  fetchProviderSource,
  mkSdk,
  langArgNames,
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
      in
      {
        name = lang;
        value = mkSdk "lib/with-sdks.nix" lang (
          {
            inherit (args) version;
            meta = args.meta or { };
            inherit src;

            # Lang-qualified so the provider and each of its SDKs get distinct
            # derivation names. An unqualified `repo` makes every store path,
            # build log line and `nix flake check` entry read the same. This
            # matches the flattened `packages.<name>-sdk-<lang>` output the
            # flake module already produces. A per-SDK `pname` still wins,
            # since `args.${argName}` merges last.
            pname = "${args.repo}-sdk-${lang}";
          }
          // args.${argName}
        );
      }
    ) argNames
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
