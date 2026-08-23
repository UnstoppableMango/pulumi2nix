# Coverage for lib/src-name.nix, the other half of what a caller-supplied `src`
# has to get right: narrow-sdk-src picks which files reach a build, this picks
# what `sourceRoot` prefixes them with. A wrong answer is not an eval error but
# a build one - `chmod: cannot access 'source/provider'` - minutes into a Go
# build, and only for `src` shapes no example uses, so every shape is pinned
# here instead.
#
# Assertions rather than a build, because `srcName` is a pure string function
# and reproducing the mismatch for real would mean building a whole provider.
{
  lib,
  pkgs,
  srcName,
}:
let
  fixture = ./fixtures/provider;

  # The name unpackPhase will actually leave behind, worked out the way stdenv
  # gets there rather than the way lib/src-name.nix does, so these expectations
  # are independent of the implementation instead of a restatement of it: taking
  # a source as a build input copies it into the store under a name Nix derives
  # from it, and stripHash then drops the leading 32-char hash and its dash.
  # `builtins.path` performs that same copy and hands back that same name.
  unpacked = src: builtins.substring 33 (-1) (baseNameOf (builtins.path { path = src; }));

  # `builtins.path` copies at eval time and hands back a string, so this is a
  # plain store-path string naming a tree that exists right now.
  storePathString = builtins.path {
    name = "src-name-fixture";
    path = fixture;
  };

  # The same store path as a path value, which is what a checkout already
  # realized in the store coerces to. Its basename is `<hash>-<name>` before the
  # copy above puts a second hash in front of it, and that doubling is what makes
  # it the shape lib/src-name.nix used to get wrong. Built by re-parsing the
  # string rather than interpolating a path, because interpolating one would copy
  # it into the store a second time and defeat the point.
  storePath = /. + (builtins.unsafeDiscardStringContext storePathString);

  # An unbuilt derivation, the shape the default `fetchFromGitHub` produces.
  # Never realized here; only its `name` is read.
  fetched = pkgs.runCommandLocal "src-name-fixture-fetched" { } "cp -r ${fixture} $out";

  cases = {
    # A fetcher output answers from `.name`, and has to keep doing so: the
    # store-path reasoning below would be wrong for it, since the fetch has no
    # output path yet to reason about.
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

    # The regression guards. Both are path values under the store, so both get
    # copied in again under their full basename; before the `builtins.isPath`
    # branch the store-prefix test stripped 33 more characters off names that
    # had no second hash to give, which for the second case is the whole name.
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
