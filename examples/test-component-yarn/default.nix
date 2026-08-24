{
  lib,
  pkgs,
  pulumi2nix,
  ...
}:
{
  pulumi.componentPackages.test-component-yarn = {
    version = "0.0.1";
    src = ./.;

    schemaArgs = {
      languagePlugin = pkgs.pulumiPackages.pulumi-nodejs;
      yarnLockFile = ./yarn.lock;
      yarnDepsHash = "sha256-fuqeLgU9n3xKy/fvxX7I+Kp0Pd8urfUTu4zdroWcCDw=";
    };

    sdks = {
      nodejs = {
        languagePlugin = pkgs.pulumiPackages.pulumi-nodejs;
        lockFile = ./generated-sdk/nodejs/package-lock.json;
        npmDepsHash = "sha256-UsdMjbXRdDB+nv5KKVxXxEZgPI/JfCBDEnT+IY807xg=";
      };

      go = {
        languagePlugin = pkgs.pulumiPackages.pulumi-go;
        importBasePath = "github.com/UnstoppableMango/pulumi2nix/examples/test-component-yarn/sdk/go/testcomponentyarn";
        goMod = ./generated-sdk/go/go.mod;
        goSum = ./generated-sdk/go/go.sum;
        vendorHash = "sha256-KBwE+KOipz+yPcyF6c79ujx20Mm2qVpT3Lhk0hNhv88=";
      };

      dotnet = {
        languagePlugin = pulumi2nix.pulumiLanguageDotnet;
        nugetDeps = ./generated-sdk/dotnet/deps.json;
      };
    };

    meta = {
      description = "pulumi2nix example: yarn-based component provider via mkComponentPackage (schema + generated nodejs/go/dotnet SDKs)";
      license = lib.licenses.asl20;
      maintainers = [ ];
    };
  };
}
