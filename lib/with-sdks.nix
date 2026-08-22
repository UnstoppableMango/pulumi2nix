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

  # The base builder may fetch its own `src` internally without exposing it
  # via passthru, so fetch it again here for any <lang>Args builder that
  # needs it. Same inputs as the base builder's fetch, so it dedupes at the
  # store level instead of fetching twice.
  src = fetchFromGitHub {
    name = "source-${args.repo}-${rev}";
    inherit (args)
      owner
      repo
      hash
      ;
    inherit rev;
    fetchSubmodules = args.fetchSubmodules or false;
  };

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
