{
  lib,
  pkgs,
  pulumi2nix,
  ...
}:
{
  pulumi.componentPackages.test-component = {
    version = "0.0.1";
    src = ./.;

    schemaArgs = {
      languagePlugin = pkgs.pulumiPackages.pulumi-language-nodejs;
      lockFile = ./package-lock.json;
      npmDepsHash = "sha256-OJn3at3oJFm1SzJTipit5D+YwBkQpAfFPFK8G+7fMAQ=";
    };

    sdks = {
      nodejs = {
        languagePlugin = pkgs.pulumiPackages.pulumi-language-nodejs;
        lockFile = ./generated-sdk/nodejs/package-lock.json;
        npmDepsHash = "sha256-ebZnHsFQZFJ18CNLqRqN3iZ8mfL6wKeTTJJO7F9eV3I=";
      };

      go = {
        languagePlugin = pkgs.pulumiPackages.pulumi-go;
        importBasePath = "github.com/UnstoppableMango/pulumi2nix/examples/test-component/sdk/go/testcomponent";
        goMod = ./generated-sdk/go/go.mod;
        goSum = ./generated-sdk/go/go.sum;
        vendorHash = "sha256-KBwE+KOipz+yPcyF6c79ujx20Mm2qVpT3Lhk0hNhv88=";
      };

      dotnet = {
        languagePlugin = pulumi2nix.pulumiLanguageDotnet;
        nugetDeps = ./generated-sdk/dotnet/deps.json;

        # `pulumi package gen-sdk --language dotnet` fetches
        # pulumi_logo_64x64.png from raw.githubusercontent.com while writing the
        # SDK, so this build cannot succeed in a sandbox. Kept out of `checks`
        # until that is fixed; see TODO.md.
        exposeCheck = false;
      };
    };

    meta = {
      description = "pulumi2nix example: minimal component provider via mkComponentPackage (schema + generated nodejs/go/dotnet SDKs)";
      license = lib.licenses.asl20;
      maintainers = [ ];
    };
  };
}
