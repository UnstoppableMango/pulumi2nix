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
  dotnetArgs = {
    languagePlugin = pulumiLanguageDotnet;
    nugetDeps = ./generated-sdk/dotnet/deps.json;
  };
  meta = {
    description = "pulumi2nix example: minimal component provider via mkComponentPackage (schema + generated nodejs/dotnet SDKs)";
    license = lib.licenses.asl20;
    maintainers = [ ];
  };
}
