{ lib, mkPulumiSchema }:
mkPulumiSchema rec {
  owner = "pulumi";
  repo = "pulumi-command";
  version = "0.9.0";
  rev = "v${version}";
  hash = "sha256-VnbtPhMyTZ4Oy+whOK6Itr2vqUagwZUODONL13fjMaU=";
  vendorHash = "sha256-MBWDEVA29uzHD3B/iPe68ntGjMM1SCTDq/TL+NgMc6c=";
  cmdGen = "pulumi-gen-command";
  extraLdflags = [ "-X github.com/pulumi/${repo}/provider/pkg/version.Version=v${version}" ];
  # pulumi-gen-command's gen tool takes an explicit output path rather than
  # a "schema" subcommand (see provider/cmd/pulumi-gen-command/main.go).
  schemaCommand = "${cmdGen} schema.json --version ${version}";
  meta = {
    description = "pulumi2nix example: pulumi-command schema.json via mkPulumiSchema";
    homepage = "https://github.com/pulumi/pulumi-command";
    license = lib.licenses.asl20;
    maintainers = [ ];
  };
}
