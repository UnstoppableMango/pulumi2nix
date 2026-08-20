{
  lib,
  fetchFromGitHub,
  sdkBuilders,
}:
{
  base,
  ...
}@args:
let
  langArgNames = lib.filter (name: name != "pythonArgs" && lib.hasSuffix "Args" name) (
    builtins.attrNames args
  );

  # The base builder may fetch its own `src` internally without exposing it
  # via passthru, so a source fetch is needed here too for any <lang>Args
  # builder that needs it (e.g. to read sdk/nodejs). Same inputs as the base
  # builder's fetch, so it dedupes at the store level rather than actually
  # fetching twice.
  src = fetchFromGitHub {
    name = "source-${args.repo}-${args.rev}";
    inherit (args)
      owner
      repo
      rev
      hash
      ;
    fetchSubmodules = args.fetchSubmodules or false;
  };

  mkSdk =
    lang: langArgs:
    (sdkBuilders.${lang}
      or (throw "lib/with-sdks.nix: no SDK builder registered for language '${lang}'")
    )
      langArgs;

  extraSdks = lib.listToAttrs (
    map (argName: {
      name = lib.removeSuffix "Args" argName;
      value = mkSdk (lib.removeSuffix "Args" argName) (
        {
          inherit (args) meta version;
          inherit src;
          pname = args.repo;
        }
        // args.${argName}
      );
    }) langArgNames
  );
in
if extraSdks == { } then
  base
else
  base
  // {
    passthru = base.passthru // {
      sdks = base.passthru.sdks // extraSdks;
    };
  }
