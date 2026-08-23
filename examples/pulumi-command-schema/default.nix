{ lib, ... }:
let
  repo = "pulumi-command";
  version = "0.9.0";
in
{
  # Named for its mechanism rather than `pulumi-command-schema`, which the
  # pulumi-command provider already claims via its flattened `passthru.schema`.
  pulumi.nativeSchemas.pulumi-command-gen-schema = {
    inherit repo version;

    owner = "pulumi";
    hash = "sha256-VnbtPhMyTZ4Oy+whOK6Itr2vqUagwZUODONL13fjMaU=";
    vendorHash = "sha256-MBWDEVA29uzHD3B/iPe68ntGjMM1SCTDq/TL+NgMc6c=";
    cmdGen = "pulumi-gen-command";
    extraLdflags = [ "-X github.com/pulumi/${repo}/provider/pkg/version.Version=v${version}" ];

    meta = {
      description = "pulumi2nix example: pulumi-command schema.json via mkPulumiSchema";
      homepage = "https://github.com/pulumi/pulumi-command";
      license = lib.licenses.asl20;
      maintainers = [ ];
    };
  };
}
