{ lib, pkgs, ... }:
{
  # Named for its mechanism (`pulumi package get-schema`) rather than
  # `test-component-schema`, which the test-component package already claims via
  # its flattened `passthru.schema`. `pname` defaults to the attribute name.
  pulumi.componentSchemas.test-component-get-schema = {
    version = "0.0.1";
    src = ./.;
    languagePlugin = pkgs.pulumiPackages.pulumi-language-nodejs;
    lockFile = ./package-lock.json;
    npmDepsHash = "sha256-OJn3at3oJFm1SzJTipit5D+YwBkQpAfFPFK8G+7fMAQ=";

    meta = {
      description = "pulumi2nix example: minimal component-provider schema.json via mkComponentSchema";
      license = lib.licenses.asl20;
      maintainers = [ ];
    };
  };
}
