# Builds a provider repo's schema generation tool: `cmd/pulumi-tfgen-<name>` for
# a bridged provider, `cmd/pulumi-gen-<name>` for a native one.
#
# One artifact, one builder. Both `mkSchema` and `mkSdkSource`'s gen-tool
# producer take the result as an input rather than building their own copy, so
# a provider that needs the tool twice pays for it once.
#
# `meta.mainProgram` is set to `cmdGen` so a consumer can recover the binary
# name from the derivation alone.
{
  buildGoModule,
  fetchProviderSource,
  srcName,
}:
{
  version,
  vendorHash,
  cmdGen,
  src ? fetchProviderSource "mk-gen-tool.nix" args,
  sourceRoot ? "${srcName src}/provider",
  extraLdflags ? [ ],
  env ? { },
  meta ? { },
  ...
}@args:
buildGoModule {
  pname = cmdGen;

  inherit
    src
    version
    vendorHash
    env
    sourceRoot
    ;

  subPackages = [ "cmd/${cmdGen}" ];

  doCheck = false;

  ldflags = [
    "-s"
    "-w"
  ]
  ++ extraLdflags;

  meta = meta // {
    mainProgram = cmdGen;
  };
}
