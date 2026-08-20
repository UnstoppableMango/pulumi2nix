{
  callPackage,
  nixpkgsPath,
}:
callPackage "${nixpkgsPath}/pkgs/by-name/pu/pulumi/extra/mk-pulumi-package.nix" { }
