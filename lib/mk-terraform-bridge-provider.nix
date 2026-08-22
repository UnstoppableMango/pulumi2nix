{
  callPackage,
  nixpkgsPath,
  mkTerraformBridgeSchema,
}:
let
  base = callPackage "${nixpkgsPath}/pkgs/by-name/pu/pulumi/extra/mk-pulumi-package.nix" { };
in
args:
(base args).overrideAttrs (old: {
  passthru = old.passthru // {
    schema = mkTerraformBridgeSchema args;
  };
})
