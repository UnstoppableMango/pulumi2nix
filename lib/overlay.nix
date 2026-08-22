# Nixpkgs overlay exposing every lib/default.nix builder as a top-level
# pkgs attribute, pre-instantiated against `final` (so no caller needs to
# thread `pkgs` through manually).
final: prev: import ./default.nix { pkgs = final; }
