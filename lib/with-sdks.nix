{
  lib,
  fetchFromGitHub,
  sdkBuilders,
  langArgNames,
}:
{
  base,
  ...
}@args:
let
  argNames = langArgNames args;

  rev = args.rev or "v${args.version}";

  # Callers that already resolved a `src` (mkTerraformBridgeProvider does)
  # pass it through so the <lang>Args builders share it. Standalone callers
  # wrapping a base derivation built elsewhere get a fallback fetch instead;
  # its inputs match the usual base-builder fetch, so it dedupes at the store
  # level rather than fetching twice.
  fetchedSrc = fetchFromGitHub {
    name = "source-${args.repo}-${rev}";
    owner = args.owner or (throw "with-sdks.nix: `owner` is required unless `src` is supplied");
    hash = args.hash or (throw "with-sdks.nix: `hash` is required unless `src` is supplied");
    inherit (args) repo;
    inherit rev;
    fetchSubmodules = args.fetchSubmodules or false;
  };

  src = args.src or fetchedSrc;

  mkSdk =
    lang: langArgs:
    (sdkBuilders.${lang}
      or (throw "lib/with-sdks.nix: no SDK builder registered for language '${lang}' (available: ${lib.concatStringsSep ", " (builtins.attrNames sdkBuilders)})")
    )
      langArgs;

  extraSdks = lib.listToAttrs (
    map (argName: {
      name = lib.removeSuffix "Args" argName;
      value = mkSdk (lib.removeSuffix "Args" argName) (
        {
          inherit (args) version;
          meta = args.meta or { };
          inherit src;
          pname = args.repo;
        }
        // args.${argName}
      );
    }) argNames
  );
in
if extraSdks == { } then
  base
else
  base.overrideAttrs (old: {
    passthru = old.passthru // {
      sdks = old.passthru.sdks // extraSdks;
    };
  })
