{ }:
{
  # Wraps nixpkgs' own Go/Terraform-bridge Pulumi provider builder
  # (`pkgs/by-name/pu/pulumi/extra/mk-pulumi-package.nix`, found via
  # `nixpkgsPath`) and adds composable per-language SDK builders
  # (currently: nodejs) alongside the python SDK nixpkgs already provides.
  mkPulumiPackage =
    {
      pkgs,
      nixpkgsPath,
    }:
    pkgs.callPackage ./mk-pulumi-package.nix { inherit nixpkgsPath; };
}
