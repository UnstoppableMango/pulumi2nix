# `sourceRoot` is relative to the directory unpackPhase leaves behind, which is
# named after the src. Fetcher outputs carry that name as an attribute; a plain
# path or store-path string doesn't, so recover it the way stdenv's stripHash
# does - drop the 32-char store hash and its separating dash.
#
# This covers the narrowed sources lib/narrow-sdk-src.nix hands the SDK builders
# too: `lib.fileset.toSource` builds on `lib.cleanSourceWith`, whose result
# carries `name = "source"`, so `sourceRoot` becomes `source/sdk/<lang>`.
{ lib }:
src:
src.name or (
  let
    path = toString src;
    base = baseNameOf path;
  in
  if lib.hasPrefix builtins.storeDir path then builtins.substring 33 (-1) base else base
)
