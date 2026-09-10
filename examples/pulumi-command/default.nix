{ lib, ... }:
let
  repo = "pulumi-command";
  version = "0.9.0";
  cmdGen = "pulumi-gen-command";
in
{
  pulumi.nativeProviders.${repo} = {
    inherit repo version cmdGen;

    owner = "pulumi";
    hash = "sha256-VnbtPhMyTZ4Oy+whOK6Itr2vqUagwZUODONL13fjMaU=";
    vendorHash = "sha256-MBWDEVA29uzHD3B/iPe68ntGjMM1SCTDq/TL+NgMc6c=";
    cmdRes = "pulumi-resource-command";
    extraLdflags = [ "-X github.com/pulumi/${repo}/provider/pkg/version.Version=v${version}" ];

    __darwinAllowLocalNetworking = true;

    sdks = {
      nodejs = {
        lockFile = ./package-lock.json;
        npmDepsHash = "sha256-U9Ez1fB0Mpau2n4Q+A4I+ZRSMnhGfAxJBqPtIMyEL8c=";
      };
      go.vendorHash = "sha256-AHCeuby00woF/OQIwHjEp1Y92ANbewjQSk/nAc9qTgE=";
      dotnet.nugetDeps = ./deps.json;
      python = { };
    };

    meta = {
      description = "pulumi2nix example: pulumi-command via mkPulumiPackage + withSdks (nodejs SDK layering)";
      mainProgram = "pulumi-resource-command";
      homepage = "https://github.com/pulumi/pulumi-command";
      license = lib.licenses.asl20;
      maintainers = [ ];
    };
  };
}
