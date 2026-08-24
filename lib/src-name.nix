# `sourceRoot` is relative to the directory unpackPhase leaves behind, which is
# named after the src. Fetcher outputs carry that name as an attribute; a plain
# path or store-path string doesn't, so work out what stdenv's stripHash leaves
# behind instead. This also covers the narrowed sources lib/narrow-sdk-src.nix
# hands the SDK builders: `lib.fileset.toSource` carries `name = "source"`, so
# `sourceRoot` becomes `source/sdk/<lang>`.
{ lib }:
src:
src.name or (
  let
    path = toString src;
    base = baseNameOf path;
  in
  # What separates the two cases is whether the value is *already* the build
  # input or gets copied to become one. A store-path string is already a store
  # path, used directly with no copy, so the one hash it carries is the one
  # stripHash removes. Everything else - a path value, in or out of the store -
  # is copied in under a name Nix derives from its basename, adding a second
  # hash on top; stripping twice off a path already in the store would name a
  # directory unpackPhase never created.
  if !builtins.isPath src && lib.hasPrefix builtins.storeDir path then
    builtins.substring 33 (-1) base
  else
    base
)
