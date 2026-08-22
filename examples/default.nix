{
  pkgs,
  nixpkgsPath,
  flakeLib,
}:
let
  mkTerraformBridgeProvider = flakeLib.mkTerraformBridgeProvider { inherit pkgs nixpkgsPath; };
  mkPulumiPackage = flakeLib.mkPulumiPackage { inherit pkgs nixpkgsPath; };
  mkPulumiSchema = flakeLib.mkPulumiSchema { inherit pkgs; };
in
{
  pulumi-random = pkgs.callPackage ./pulumi-random { inherit mkTerraformBridgeProvider; };
  pulumi-command = pkgs.callPackage ./pulumi-command { inherit mkPulumiPackage; };
  pulumi-random-schema = pkgs.callPackage ./pulumi-random-schema { inherit mkPulumiSchema; };
  pulumi-command-schema = pkgs.callPackage ./pulumi-command-schema { inherit mkPulumiSchema; };
}
