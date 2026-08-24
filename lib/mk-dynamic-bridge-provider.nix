{
  buildGoModule,
  fetchProviderSource,
}:
{
  owner ? "pulumi",
  repo ? "pulumi-terraform-bridge",
  rev ? "v${version}",
  versionString ? rev,
  version,
  hash ? throw "mk-dynamic-bridge-provider.nix: `hash` is required unless `src` is supplied",
  src ? fetchProviderSource "mk-dynamic-bridge-provider.nix" {
    inherit
      owner
      repo
      rev
      hash
      fetchSubmodules
      ;
  },
  vendorHash,
  extraLdflags ? [ ],
  env ? { },
  fetchSubmodules ? false,
  meta ? { },
  ...
}@args:
buildGoModule (
  (removeAttrs args [
    "owner"
    "repo"
    "rev"
    "versionString"
    "hash"
    "vendorHash"
    "extraLdflags"
    "fetchSubmodules"
  ])
  // {
    pname = "pulumi-terraform-provider";
    inherit
      version
      vendorHash
      env
      meta
      src
      ;

    subPackages = [ "dynamic" ];

    doCheck = false;

    ldflags = [
      "-s"
      "-w"
      "-X"
      "google.golang.org/protobuf/reflect/protoregistry.conflictPolicy=ignore"
      "-X"
      "github.com/pulumi/pulumi-terraform-bridge/v3/dynamic/version.version=${versionString}"
    ]
    ++ extraLdflags;

    postInstall = ''
      mv $out/bin/dynamic $out/bin/pulumi-resource-terraform-provider
    '';
  }
)
