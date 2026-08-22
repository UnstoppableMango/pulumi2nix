{ lib, mkDynamicBridgeProvider }:
mkDynamicBridgeProvider {
  version = "3.137.0";
  hash = "sha256-e8dvKVY3K5NpS4hlyaSYyXsxIxnBTCFMhxyOa7YjFKw=";
  vendorHash = "sha256-57r3m0fgqJ2D+uueeY7XJZqf4w/5DWJhq07o86M8pGg=";
  meta = {
    description = "pulumi2nix example: pulumi-terraform-provider via mkDynamicBridgeProvider";
    mainProgram = "pulumi-resource-terraform-provider";
    homepage = "https://github.com/pulumi/pulumi-terraform-provider";
    license = lib.licenses.asl20;
    maintainers = [ ];
  };
}
