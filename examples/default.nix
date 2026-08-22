{
  pkgs,
  nixpkgsPath,
  flakeLib,
}:
let
  mkTerraformBridgeProvider = flakeLib.mkTerraformBridgeProvider { inherit pkgs nixpkgsPath; };
  mkPulumiPackage = flakeLib.mkPulumiPackage { inherit pkgs nixpkgsPath; };
  mkTerraformBridgeSchema = flakeLib.mkTerraformBridgeSchema { inherit pkgs; };
  mkPulumiSchema = flakeLib.mkPulumiSchema { inherit pkgs; };
  mkComponentSchema = flakeLib.mkComponentSchema { inherit pkgs; };
  mkComponentPackage = flakeLib.mkComponentPackage { inherit pkgs; };
in
{
  pulumi-random = pkgs.callPackage ./pulumi-random { inherit mkTerraformBridgeProvider; };
  pulumi-command = pkgs.callPackage ./pulumi-command { inherit mkPulumiPackage; };
  pulumi-random-schema = pkgs.callPackage ./pulumi-random-schema { inherit mkTerraformBridgeSchema; };
  pulumi-command-schema = pkgs.callPackage ./pulumi-command-schema { inherit mkPulumiSchema; };
  test-component-schema = pkgs.callPackage ./test-component-schema { inherit mkComponentSchema; };
  test-component = pkgs.callPackage ./test-component {
    inherit mkComponentPackage;
    pulumiLanguageDotnet = flakeLib.pulumiLanguageDotnet { inherit pkgs; };
  };
}
