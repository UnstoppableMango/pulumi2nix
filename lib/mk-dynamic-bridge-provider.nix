# A dynamically bridged provider wraps *any* Terraform provider at runtime
# (via `pulumi package add terraform-provider ...` parameterization) instead
# of being generated ahead-of-time for one specific upstream provider like
# mkTerraformBridgeProvider's forks are. It is therefore a single, generic
# `pulumi-resource-terraform-provider` binary built straight from
# pulumi/pulumi-terraform-bridge's `./dynamic` package - there is no
# per-provider owner/repo/schema to plug in here.
#
# Source lives in pulumi/pulumi-terraform-bridge (the `dynamic` directory is
# a plain subpackage of that module, not its own go.mod); pulumi/pulumi-terraform-provider
# only hosts releases built from it. See that repo's dynamic/README.md and
# dynamic/Makefile.
{
  buildGoModule,
  fetchProviderSource,
}:
# `src` defaults to a fetch of `owner`/`repo`/`rev`/`hash`; pass it to build from
# a local checkout or a different fetcher. `hash` is only forced by that default,
# so a caller supplying `src` can omit it.
#
# `rev` names the source; `versionString` is what the binary reports, and the two
# are separate because they genuinely differ here. `pulumi/pulumi-terraform-provider`
# only hosts docs and releases: the code is `pulumi/pulumi-terraform-bridge`'s
# `dynamic/` directory, and a `pulumi-terraform-provider` release names the bridge
# *commit* it was generated from rather than a bridge tag. So a release-accurate
# build is `rev = "<sha>"` with `versionString = "v1.1.3"`. `versionString`
# defaults to `rev`, which is correct for every caller where the release tag and
# the source revision are the same string.
{
  owner ? "pulumi",
  repo ? "pulumi-terraform-bridge",
  rev ? "v${version}",
  versionString ? rev,
  version,
  hash ? throw "mk-dynamic-bridge-provider.nix: `hash` is required unless `src` is supplied",
  # Passed explicitly rather than as `args`: this builder defaults `owner`/`repo`
  # in its own formals, which another formal's default expression can see but
  # the `@args` binding cannot.
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

    # `go build ./dynamic` names the binary after the package directory;
    # upstream's own Makefile/goreleaser call it pulumi-resource-terraform-provider.
    postInstall = ''
      mv $out/bin/dynamic $out/bin/pulumi-resource-terraform-provider
    '';
  }
)
