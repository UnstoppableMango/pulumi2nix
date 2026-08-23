{ lib, ... }:
let
  repo = "pulumi-random";
  version = "4.14.0";
in
{
  # Named for its mechanism rather than `pulumi-random-schema`, which the
  # pulumi-random provider already claims via its flattened `passthru.schema`.
  pulumi.terraformBridgeSchemas.pulumi-random-tfgen-schema = {
    inherit repo version;

    owner = "pulumi";
    hash = "sha256-1MR7zWNBDbAUoRed7IU80PQxeH18x95MKJKejW5m2Rs=";
    vendorHash = "sha256-YDuF89F9+pxVq4TNe5l3JlbcqpnJwSTPAP4TwWTriWA=";
    cmdGen = "pulumi-tfgen-random";
    extraLdflags = [ "-X github.com/pulumi/${repo}/provider/v4/pkg/version.Version=v${version}" ];

    meta = {
      description = "pulumi2nix example: pulumi-random schema.json via mkTerraformBridgeSchema";
      homepage = "https://github.com/pulumi/pulumi-random";
      license = lib.licenses.asl20;
      maintainers = [ ];
    };
  };
}
