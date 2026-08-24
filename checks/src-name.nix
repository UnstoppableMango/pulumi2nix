# Coverage for lib/src-name.nix, which picks what `sourceRoot` prefixes files
# with (narrow-sdk-src picks which files reach a build). A wrong answer is not
# an eval error but a build one - `chmod: cannot access 'source/provider'` -
# minutes into a Go build, and only for `src` shapes no example uses, so every
# shape is pinned here as assertions instead of a build, since `srcName` is a
# pure string function.
{
  lib,
  pkgs,
  srcName,
}:
let
  fixture = ./fixtures/provider;

  # The name unpackPhase leaves behind, worked out the way stdenv gets there
  # rather than the way lib/src-name.nix does, so these expectations are
  # independent of the implementation: taking a source as a build input copies
  # it into the store under a name Nix derives from it, and stripHash drops
  # the leading 32-char hash and its dash. `builtins.path` performs that same
  # copy and hands back that same name.
  unpacked = src: builtins.substring 33 (-1) (baseNameOf (builtins.path { path = src; }));

  # `builtins.path` copies at eval time and hands back a string, so this is a
  # plain store-path string naming an existing tree.
  storePathString = builtins.path {
    name = "src-name-fixture";
    path = fixture;
  };

  # The same store path as a path value, matching what an already-realized
  # checkout coerces to; its double-hashed basename (the copy above adds a
  # second hash in front of `<hash>-<name>`) is the shape lib/src-name.nix
  # must handle. Built by re-parsing the string rather than interpolating a
  # path, since interpolating would copy it into the store a second time.
  storePath = /. + (builtins.unsafeDiscardStringContext storePathString);

  # An unbuilt derivation, the shape the default `fetchFromGitHub` produces.
  # Never realized here; only its `name` is read.
  fetched = pkgs.runCommandLocal "src-name-fixture-fetched" { } "cp -r ${fixture} $out";

  cases = {
    # A fetcher output answers from `.name`: the store-path reasoning below
    # would be wrong for it, since an unbuilt fetch has no output path to
    # reason about.
    "derivation with .name" = {
      actual = srcName fetched;
      expected = fetched.name;
    };

    # What narrow-sdk-src hands the SDK builders. `lib.fileset.toSource` builds
    # on `lib.cleanSourceWith`, whose result is a set carrying `name = "source"`,
    # so it takes the `.name` branch and never reaches the path reasoning.
    "lib.fileset.toSource result" = {
      actual = srcName (
        lib.fileset.toSource {
          root = fixture;
          fileset = fixture + "/sdk";
        }
      );
      expected = "source";
    };

    # The regression guards: both are path values under the store, so both get
    # copied in again under their full basename. Without the `builtins.isPath`
    # branch, the store-prefix test would strip 33 characters off names that
    # have no second hash to give, which for the second case is the whole name.
    "path already in the store" = {
      actual = srcName storePath;
      expected = unpacked storePath;
    };

    "path under a store path" = {
      actual = srcName fixture;
      expected = unpacked fixture;
    };

    # Unchanged by the `builtins.isPath` branch, which returns the same basename
    # the fallback already did. Pinned so the branch cannot start mangling it.
    "path outside the store" = {
      actual = srcName (/. + "/example/checkout");
      expected = "checkout";
    };

    # A store-path string is already a store path, so it becomes the build input
    # directly, with no copy and no second hash. Its own hash is therefore the
    # one stripHash removes, which is the store-prefix branch's job and stays
    # untouched by the path branch above it.
    "store-path string" = {
      actual = srcName storePathString;
      expected = "src-name-fixture";
    };
  };

  failures = lib.mapAttrsToList (
    name: case: "  ${name}: got '${case.actual}', want '${case.expected}'"
  ) (lib.filterAttrs (_: case: case.actual != case.expected) cases);
in
assert lib.assertMsg (failures == [ ]) ''
  lib/src-name.nix disagrees with the directory unpackPhase leaves behind:
  ${lib.concatStringsSep "\n" failures}'';
pkgs.runCommandLocal "src-name" { } "touch $out"
