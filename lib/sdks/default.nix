{ callPackage }:
{
  nodejs = callPackage ./nodejs.nix { };
  go = callPackage ./go.nix { };
  dotnet = callPackage ./dotnet.nix { };
}
