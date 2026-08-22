{ callPackage }:
{
  nodejs = callPackage ./nodejs.nix { };
  yarnNodejs = callPackage ./yarn-nodejs.nix { };
  go = callPackage ./go.nix { };
  dotnet = callPackage ./dotnet.nix { };
}
