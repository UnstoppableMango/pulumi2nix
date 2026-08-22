{
  pkgs,
  flakeLib,
}:
let
  mkTerraformBridgeProvider = flakeLib.mkTerraformBridgeProvider;
  mkDynamicBridgeProvider = flakeLib.mkDynamicBridgeProvider;
  mkPulumiPackage = flakeLib.mkPulumiPackage;
  mkTerraformBridgeSchema = flakeLib.mkTerraformBridgeSchema;
  mkPulumiSchema = flakeLib.mkPulumiSchema;
  mkComponentSchema = flakeLib.mkComponentSchema;
  mkComponentPackage = flakeLib.mkComponentPackage;
in
{
  pulumi-random = pkgs.callPackage ./pulumi-random { inherit mkTerraformBridgeProvider; };
  pulumi-terraform-provider = pkgs.callPackage ./pulumi-terraform-provider {
    inherit mkDynamicBridgeProvider;
  };
  pulumi-command = pkgs.callPackage ./pulumi-command { inherit mkPulumiPackage; };
  pulumi-random-schema = pkgs.callPackage ./pulumi-random-schema { inherit mkTerraformBridgeSchema; };
  pulumi-command-schema = pkgs.callPackage ./pulumi-command-schema { inherit mkPulumiSchema; };
  test-component-schema = pkgs.callPackage ./test-component-schema { inherit mkComponentSchema; };
  test-component = pkgs.callPackage ./test-component {
    inherit mkComponentPackage;
    pulumiLanguageDotnet = flakeLib.pulumiLanguageDotnet;
  };
}
