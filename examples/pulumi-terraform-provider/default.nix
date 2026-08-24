{ lib, ... }:
{
  pulumi.dynamicBridgeProviders.pulumi-terraform-provider = {
    version = "1.1.3";
    rev = "484f8987228cbec779e11f593bc48c79c49d4f08";
    versionString = "v1.1.3";
    hash = "sha256-NGZONXglwkyptkLVdXVaoWCqvYY4+UAII9KFpD9aRss=";
    vendorHash = "sha256-cVFwjrL3FDeXkKz/wAyqjsY99RAN0ed3NBWviBq8aV0=";

    meta = {
      description = "pulumi2nix example: pulumi-terraform-provider via mkDynamicBridgeProvider";
      mainProgram = "pulumi-resource-terraform-provider";
      homepage = "https://github.com/pulumi/pulumi-terraform-provider";
      license = lib.licenses.asl20;
      maintainers = [ ];
    };
  };
}
