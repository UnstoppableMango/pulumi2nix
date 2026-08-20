{
  lib,
  callPackage,
  nixpkgsPath,
}:
let
  mkSchema = callPackage ./mk-schema.nix { };
  mkTerraformBridgeSchema = callPackage ./mk-terraform-bridge-schema.nix { inherit mkSchema; };
  mkPulumiSchema = callPackage ./mk-pulumi-schema.nix { inherit mkSchema; };
  mkTerraformBridgeProvider = callPackage ./mk-terraform-bridge-provider.nix {
    inherit nixpkgsPath mkTerraformBridgeSchema;
  };
  sdkBuilders = callPackage ./sdks { };
  withSdks = callPackage ./with-sdks.nix { inherit sdkBuilders; };
in
args@{ ... }:
let
  langArgNames = lib.filter (name: name != "pythonArgs" && lib.hasSuffix "Args" name) (
    builtins.attrNames args
  );
  base = mkTerraformBridgeProvider (removeAttrs args langArgNames);
  withSdksResult = withSdks (args // { inherit base; });
in
withSdksResult
// {
  # mkPulumiPackage's native + SDK-layering use case gets the native gen-tool
  # schema convention, overriding the terraform-bridge one `base` attached.
  passthru = withSdksResult.passthru // {
    schema = mkPulumiSchema args;
  };
}
