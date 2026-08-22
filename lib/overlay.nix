# Nixpkgs overlay exposing every lib/default.nix builder as a top-level
# pkgs attribute, pre-instantiated against `final` (so no caller needs to
# thread `pkgs` through manually). Every lib/default.nix attr takes
# exactly `{ pkgs, ... }`, so this generic `mapAttrs` works for all of
# them without special-casing any one of them.
final: prev:
let
  flakeLib = import ./default.nix { };
in
builtins.mapAttrs (_: builder: builder { pkgs = final; }) flakeLib
