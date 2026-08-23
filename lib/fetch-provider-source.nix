# The default `src` fetch shared by every builder that starts from a Pulumi
# provider repo. Kept in one place so the derivation name, the `v${version}`
# rev convention, and the missing-arg errors stay identical across builders;
# `caller` only names the file those errors come from.
#
# Only `or`-guarded lookups are used, so this stays callable from a formal's
# default expression, where the `@args` binding sees just the caller's raw
# attrset and none of the defaults.
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
