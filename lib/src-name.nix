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
  # The two cases differ in how many hashes end up in front of the name.
  #
  # A path value is *copied* into the store to become a build input, under a
  # name Nix derives from its own basename, so the store adds one hash on top of
  # whatever that basename already was. stripHash peels off exactly that one,
  # leaving the basename whole. For a path that already lives in the store the
  # basename is itself `<hash>-<name>`, and stripping a second time would name a
  # directory unpackPhase never created - the mismatch that made `sourceRoot`
  # point at nothing.
  #
  # A store-path string, by contrast, is already a store path and is used as the
  # input directly, no copy and no second hash, so its one hash is the one
  # stripHash removes.
  if builtins.isPath src then
    base
  else if lib.hasPrefix builtins.storeDir path then
    builtins.substring 33 (-1) base
  else
    base
)
