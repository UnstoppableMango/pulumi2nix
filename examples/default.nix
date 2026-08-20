{
  pkgs,
  nixpkgsPath,
  flakeLib,
}:
let
  mkTerraformBridgeProvider = flakeLib.mkTerraformBridgeProvider { inherit pkgs nixpkgsPath; };
  mkPulumiPackage = flakeLib.mkPulumiPackage { inherit pkgs nixpkgsPath; };
in
{
  pulumi-random = pkgs.callPackage ./pulumi-random { inherit mkTerraformBridgeProvider; };
  pulumi-command = pkgs.callPackage ./pulumi-command { inherit mkPulumiPackage; };
}
