{ }:
{
  # Wraps nixpkgs' own Go/Terraform-bridge Pulumi provider builder
  # (`pkgs/by-name/pu/pulumi/extra/mk-pulumi-package.nix`, found via
  # `nixpkgsPath`) and layers `withSdks` on top to add composable
  # per-language SDK builders (currently: nodejs) alongside the python SDK
  # nixpkgs already provides.
  mkPulumiPackage =
    { pkgs, nixpkgsPath }:
    pkgs.callPackage ./mk-pulumi-package.nix { inherit nixpkgsPath; };

  # The terraform-bridge base builder on its own, without any SDK layering.
  mkTerraformBridgeProvider =
    { pkgs, nixpkgsPath }:
    pkgs.callPackage ./mk-terraform-bridge-provider.nix { inherit nixpkgsPath; };

  # Attaches `<lang>Args`-driven SDK builds to any base derivation's
  # `passthru.sdks`, not just a terraform-bridge one.
  withSdks =
    { pkgs }:
    pkgs.callPackage ./with-sdks.nix { sdkBuilders = pkgs.callPackage ./sdks { }; };

  # Registry of per-language SDK builders (lang name -> builder function),
  # for composing SDK builds directly without going through `withSdks`.
  sdkBuilders =
    { pkgs }:
    pkgs.callPackage ./sdks { };
}
