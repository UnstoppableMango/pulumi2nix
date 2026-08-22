{
  callPackage,
  nixpkgsPath,
  mkTerraformBridgeSchema,
}:
let
  mkPulumiPackagePath = "${nixpkgsPath}/pkgs/by-name/pu/pulumi/extra/mk-pulumi-package.nix";
  base =
    if builtins.pathExists mkPulumiPackagePath then
      callPackage mkPulumiPackagePath { }
    else
      throw ''
        lib/mk-terraform-bridge-provider.nix: expected nixpkgs' own Pulumi
        provider builder at ${mkPulumiPackagePath}, but it doesn't exist.
        This usually means `nixpkgsPath` points at a nixpkgs revision that
        has restructured or removed
        `pkgs/by-name/pu/pulumi/extra/mk-pulumi-package.nix`. Pass a
        `nixpkgsPath` (or rely on the `pkgs.path` default) pinned to a
        nixpkgs revision where this file still exists at that location.
      '';
in
args:
(base args).overrideAttrs (old: {
  passthru = old.passthru // {
    schema = mkTerraformBridgeSchema args;
  };
})
