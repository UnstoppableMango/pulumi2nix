{ lib, ... }:
let
  repo = "pulumi-random";
  version = "4.14.0";
in
{
  pulumi.terraformBridgeProviders.${repo} = {
    inherit repo version;

    owner = "pulumi";
    hash = "sha256-1MR7zWNBDbAUoRed7IU80PQxeH18x95MKJKejW5m2Rs=";
    vendorHash = "sha256-YDuF89F9+pxVq4TNe5l3JlbcqpnJwSTPAP4TwWTriWA=";
    cmdGen = "pulumi-tfgen-random";
    cmdRes = "pulumi-resource-random";
    extraLdflags = [ "-X github.com/pulumi/${repo}/provider/v4/pkg/version.Version=v${version}" ];

    # Not a declared option: reaches buildGoModule through the submodule's
    # freeformType, the same escape hatch the builders themselves rely on.
    __darwinAllowLocalNetworking = true;

    # Deliberately not enabled here:
    #
    #   sdkDrift.languages = [ "nodejs" ];
    #
    # would emit `checks.pulumi-random-sdk-nodejs-generated` and fail, not
    # because upstream's sdk/nodejs is stale, but because tfgen cannot reproduce
    # it in the sandbox. pulumi-random's doc comments come from the vendored
    # `terraform-providers/terraform-provider-random` module's `website/docs`,
    # which nixpkgs' `go mod vendor` tree drops, so every resource regenerates
    # with plain-text descriptions instead of upstream's markdown. The check is
    # exact for providers that own their docs, which `make generate` for a
    # greenfield bridged provider is nothing but `tfgen <lang> --out sdk/<lang>`.
    #
    # A plain list here, not the `{ nodejs.languagePlugin = ...; }` attrset a
    # delegating bridge needs: this version's pulumi-terraform-bridge codegens
    # in-process, so its tfgen needs no CLI or language host on PATH. Both
    # spellings stay supported for exactly that reason.

    meta = {
      description = "pulumi2nix example: pulumi-random via mkTerraformBridgeProvider";
      mainProgram = "pulumi-resource-random";
      homepage = "https://github.com/pulumi/pulumi-random";
      license = lib.licenses.asl20;
      maintainers = [ ];
    };
  };
}
