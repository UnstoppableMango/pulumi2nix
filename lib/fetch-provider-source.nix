{ fetchFromGitHub }:
caller: args:
let
  rev = args.rev or "v${args.version}";
in
fetchFromGitHub {
  name = "source-${args.repo}-${rev}";
  owner = args.owner or (throw "${caller}: `owner` is required unless `src` is supplied");
  hash = args.hash or (throw "${caller}: `hash` is required unless `src` is supplied");
  inherit (args) repo;
  inherit rev;
  fetchSubmodules = args.fetchSubmodules or false;
}
