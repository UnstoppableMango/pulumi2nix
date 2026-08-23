{
  lib,
  mkComponentPackage,
  pulumiPackages,
  pulumiLanguageDotnet,
}:
mkComponentPackage {
  pname = "test-component";
  version = "0.0.1";
  src = ./.;
  schemaArgs = {
    languagePlugin = pulumiPackages.pulumi-language-nodejs;
    lockFile = ./package-lock.json;
    npmDepsHash = "sha256-OJn3at3oJFm1SzJTipit5D+YwBkQpAfFPFK8G+7fMAQ=";
  };
  nodejsArgs = {
    languagePlugin = pulumiPackages.pulumi-language-nodejs;
    lockFile = ./generated-sdk/nodejs/package-lock.json;
    npmDepsHash = "sha256-ebZnHsFQZFJ18CNLqRqN3iZ8mfL6wKeTTJJO7F9eV3I=";
  };
  goArgs = {
    languagePlugin = pulumiPackages.pulumi-go;
    importBasePath = "github.com/UnstoppableMango/pulumi2nix/examples/test-component/sdk/go/testcomponent";
    goMod = ./generated-sdk/go/go.mod;
    goSum = ./generated-sdk/go/go.sum;
    vendorHash = "sha256-KBwE+KOipz+yPcyF6c79ujx20Mm2qVpT3Lhk0hNhv88=";
  };
  dotnetArgs = {
    languagePlugin = pulumiLanguageDotnet;
    nugetDeps = ./generated-sdk/dotnet/deps.json;
  };
  meta = {
    description = "pulumi2nix example: minimal component provider via mkComponentPackage (schema + generated nodejs/go/dotnet SDKs)";
    license = lib.licenses.asl20;
    maintainers = [ ];
  };
}
