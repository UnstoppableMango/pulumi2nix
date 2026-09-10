{ lib }:
src:
src.name or (
  let
    path = toString src;
    base = baseNameOf path;
  in
  if !builtins.isPath src && lib.hasPrefix builtins.storeDir path then
    builtins.substring 33 (-1) base
  else
    base
)
