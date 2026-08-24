{ callPackage }:
{
  nodejs = callPackage ./npm.nix { };
  yarnNodejs = callPackage ./yarn.nix { };
  go = callPackage ./go.nix { };
  dotnet = callPackage ./dotnet.nix { };
  python = callPackage ./python.nix { };
}
