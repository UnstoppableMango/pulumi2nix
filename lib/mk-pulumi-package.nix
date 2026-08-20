{
  lib,
  callPackage,
  nixpkgsPath,
}:
let
  mkTerraformBridgeProvider = callPackage ./mk-terraform-bridge-provider.nix { inherit nixpkgsPath; };
  sdkBuilders = callPackage ./sdks { };
  withSdks = callPackage ./with-sdks.nix { inherit sdkBuilders; };
in
args@{ ... }:
let
  langArgNames = lib.filter (name: name != "pythonArgs" && lib.hasSuffix "Args" name) (
    builtins.attrNames args
  );
  base = mkTerraformBridgeProvider (removeAttrs args langArgNames);
in
withSdks (args // { inherit base; })
