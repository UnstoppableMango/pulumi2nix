{ lib, ... }:
{
  # `owner`/`repo` default to pulumi/pulumi-terraform-bridge, where the
  # `dynamic` package actually lives.
  pulumi.dynamicBridgeProviders.pulumi-terraform-provider = {
    # Pinned the way a `pulumi-terraform-provider` release actually identifies
    # itself. That repo hosts only docs and releases; the code is
    # `pulumi-terraform-bridge`'s `dynamic/` directory, and release v1.1.3 names
    # the bridge *commit* it was built from, not a bridge tag. So `rev` is that
    # SHA, `versionString` is the release tag the binary must report, and
    # `version` names the derivation.
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
