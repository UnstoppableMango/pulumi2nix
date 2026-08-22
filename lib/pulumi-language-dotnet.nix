# nixpkgs' `pulumiPackages` has `pulumi-language-{go,nodejs,python}` but no
# `pulumi-language-dotnet` - .NET codegen lives in a separate upstream repo
# (`pulumi/pulumi-dotnet`), not `pulumi/pulumi`. This fills that gap with a
# pinned build of the language host binary, for use as a `pulumi package
# gen-sdk --language dotnet` plugin alongside nixpkgs' other language hosts.
#
# `pulumi-language-dotnet/go.mod`'s pinned `pulumi/pulumi/{pkg,sdk}` version
# should track the `pulumi` CLI version in use elsewhere in this flake (see
# flake.lock) - the plugin and CLI speak the same RPC protocol version.
{
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule {
  pname = "pulumi-language-dotnet";
  version = "3.110.0";

  src = fetchFromGitHub {
    owner = "pulumi";
    repo = "pulumi-dotnet";
    rev = "6a6ecf5bc38ce372836b41f32dbbd6460e7d06c0"; # tag pulumi-language-dotnet/v3.110.0
    hash = "sha256-IGSP6aXU8mUfgPrLeIRnkR1OA3wDzqFv3/tdBloZ3Zg=";
  };

  # The language host's module root is the binary package itself (flat
  # layout: `pulumi-language-dotnet/main.go`), not a `cmd/<name>` subdir -
  # see upstream's `.goreleaser.yml` (`dir: ./pulumi-language-dotnet`) and
  # `Makefile`'s `build_language_host` target.
  modRoot = "pulumi-language-dotnet";
  subPackages = [ "." ];

  vendorHash = "sha256-axIEbD2bTthSR9X0gqx6bJV0I68xZadhxCtBzchijGA=";

  ldflags = [
    "-X"
    "github.com/pulumi/pulumi-dotnet/pulumi-language-dotnet/v3/version.Version=3.110.0"
  ];

  doCheck = false;

  meta = {
    description = "Pulumi language host for .NET programs and component providers";
    homepage = "https://github.com/pulumi/pulumi-dotnet";
    mainProgram = "pulumi-language-dotnet";
  };
}
