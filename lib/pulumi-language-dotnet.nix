{
  buildGoModule,
  fetchFromGitHub,
  fetchurl,
}:
let
  # The .NET codegen writes a logo.png beside each generated SDK's .csproj, and
  # upstream's getLogo() downloads it, so `pulumi package gen-sdk --language
  # dotnet` cannot run in a build sandbox. Fetch it here instead, with Nix's
  # fixed-output fetcher as the one thing allowed network, and patch getLogo()
  # to read this vendored copy of upstream's own hardcoded default URL.
  defaultLogo = fetchurl {
    url = "https://raw.githubusercontent.com/pulumi/pulumi/dbc96206bec722b7791a22ff50e895ab7c0abdc0/sdk/dotnet/pulumi_logo_64x64.png";
    hash = "sha256-XqrP0xs/0mafCNTqALimp4SA9s23lGIcNY9Zyv9TT+k=";
  };
in
buildGoModule {
  pname = "pulumi-language-dotnet";
  version = "3.110.0";

  src = fetchFromGitHub {
    owner = "pulumi";
    repo = "pulumi-dotnet";
    rev = "6a6ecf5bc38ce372836b41f32dbbd6460e7d06c0";
    hash = "sha256-IGSP6aXU8mUfgPrLeIRnkR1OA3wDzqFv3/tdBloZ3Zg=";
  };

  patches = [ ./patches/pulumi-language-dotnet-offline-logo.patch ];

  postPatch = ''
    substituteInPlace pulumi-language-dotnet/codegen/gen.go \
      --subst-var-by pulumiLogo ${defaultLogo}
  '';

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
