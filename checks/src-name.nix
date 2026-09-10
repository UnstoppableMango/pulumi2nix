{
  lib,
  pkgs,
  srcName,
}:
let
  fixture = ./fixtures/provider;

  unpacked = src: builtins.substring 33 (-1) (baseNameOf (builtins.path { path = src; }));

  storePathString = builtins.path {
    name = "src-name-fixture";
    path = fixture;
  };

  storePath = /. + (builtins.unsafeDiscardStringContext storePathString);

  fetched = pkgs.runCommandLocal "src-name-fixture-fetched" { } "cp -r ${fixture} $out";

  cases = {
    "derivation with .name" = {
      actual = srcName fetched;
      expected = fetched.name;
    };

    "lib.fileset.toSource result" = {
      actual = srcName (
        lib.fileset.toSource {
          root = fixture;
          fileset = fixture + "/sdk";
        }
      );
      expected = "source";
    };

    "path already in the store" = {
      actual = srcName storePath;
      expected = unpacked storePath;
    };

    "path under a store path" = {
      actual = srcName fixture;
      expected = unpacked fixture;
    };

    "path outside the store" = {
      actual = srcName (/. + "/example/checkout");
      expected = "checkout";
    };

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
