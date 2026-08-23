# `sourceRoot` is relative to the directory unpackPhase leaves behind, which is
# named after the src. Fetcher outputs carry that name as an attribute; a plain
# path or store-path string doesn't, so work out what stdenv's stripHash will
# leave behind instead.
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
  # What separates the two cases is whether the value is *already* the build
  # input or gets copied to become one.
  #
  # A store-path string is already a store path, so it is used directly: no
  # copy, and the one hash it carries is the one stripHash removes.
  #
  # Everything else - a path value, in or out of the store - is copied in under
  # a name Nix derives from its basename, so the store adds a hash on top of
  # whatever that basename already was. stripHash peels off exactly that one,
  # leaving the basename whole. Stripping a second time off a path that already
  # lives in the store would name a directory unpackPhase never created, which
  # is the mismatch that made `sourceRoot` point at nothing.
  if !builtins.isPath src && lib.hasPrefix builtins.storeDir path then
    builtins.substring 33 (-1) base
  else
    base
)
