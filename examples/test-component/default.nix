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
      languagePlugin = pkgs.pulumiPackages.pulumi-nodejs;
      lockFile = ./package-lock.json;
      npmDepsHash = "sha256-OJn3at3oJFm1SzJTipit5D+YwBkQpAfFPFK8G+7fMAQ=";
    };

    sdks = {
      nodejs = {
        languagePlugin = pkgs.pulumiPackages.pulumi-nodejs;
        lockFile = ./generated-sdk/nodejs/package-lock.json;
        npmDepsHash = "sha256-ebZnHsFQZFJ18CNLqRqN3iZ8mfL6wKeTTJJO7F9eV3I=";
      };

      go = {
        languagePlugin = pkgs.pulumiPackages.pulumi-go;
        importBasePath = "github.com/UnstoppableMango/pulumi2nix/examples/test-component/sdk/go/testcomponent";
        goMod = ./generated-sdk/go/go.mod;
        goSum = ./generated-sdk/go/go.sum;
        vendorHash = "sha256-i/0ixLhLo/u3nCC2Ecfofm/AYeXthBI4y6t6ISgPnJ4=";
      };

      dotnet = {
        languagePlugin = pulumi2nix.pulumiLanguageDotnet;
        nugetDeps = ./generated-sdk/dotnet/deps.json;
      };

      python = {
        languagePlugin = pkgs.pulumiPackages.pulumi-python;

        # The generated SDK distributes under the *schema's* package name, which
        # `pulumi package get-schema` takes from package.json, not from `pname`.
        distName = "pulumi_test_component_schema";
      };
    };

    meta = {
      description = "pulumi2nix example: minimal component provider via mkComponentPackage (schema + generated nodejs/go/dotnet SDKs)";
      license = lib.licenses.asl20;
      maintainers = [ ];
    };
  };
}
