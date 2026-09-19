# The three properties a package set claims, checked rather than asserted in a
# doc. Fixture members stand in for real providers so the check stays an
# evaluation plus two symlink trees, not a pair of Go builds.
{
  lib,
  pkgs,
  mkPackageSet,
}:
let
  # A stand-in provider: a `pulumi-resource-<name>` in `$out/bin`, declaring
  # itself the way `mkProviderPlugin` does.
  fakeProvider =
    { name, version }:
    { pulumi }:
    pkgs.runCommandLocal "pulumi-resource-${name}-${version}"
      {
        inherit version;
        meta.mainProgram = "pulumi-resource-${name}";
        passthru.sdks.nodejs = pkgs.runCommandLocal "${name}-sdk-nodejs" { } "touch $out";
      }
      ''
        mkdir -p $out/bin
        echo '#!/bin/sh' > $out/bin/pulumi-resource-${name}
        echo 'exec ${lib.getExe pulumi} "$@"' >> $out/bin/pulumi-resource-${name}
        chmod +x $out/bin/pulumi-resource-${name}
      '';

  base = mkPackageSet {
    name = "fixture";
    version = "1.0.0";
    pins = { inherit (pkgs) pulumi; };
    packages = {
      alpha = fakeProvider {
        name = "alpha";
        version = "1.2.3";
      };
      beta = fakeProvider {
        name = "beta";
        version = "4.5.6";
      };
    };
  };

  # A derived channel that replaces one member and leaves the other alone.
  derived = base.extend {
    name = "fixture-derived";
    version = "2.0.0";
    packages.beta = fakeProvider {
      name = "beta";
      version = "9.9.9";
    };
  };

  cases = {
    # The caching claim: membership and the set's own version are not inputs to
    # a member, so an unrelated override leaves its store path alone.
    "extend leaves an untouched member's path alone" = {
      actual = derived.members.alpha.drvPath;
      expected = base.members.alpha.drvPath;
    };

    "extend does replace the member it names" = {
      actual = derived.members.beta.version;
      expected = "9.9.9";
    };

    "members are built against the set's pins" = {
      actual = base.scope.pulumi.drvPath;
      expected = pkgs.pulumi.drvPath;
    };

    "the manifest records member versions" = {
      actual = base.manifestData.packages.alpha.version;
      expected = "1.2.3";
    };

    "the manifest records the plugin name, not the package name" = {
      actual = base.manifestData.packages.alpha.plugin;
      expected = "alpha";
    };

    "the set folds out per-language SDK views" = {
      actual = lib.concatStringsSep "," (lib.attrNames base.sdks.nodejs);
      expected = "alpha,beta";
    };
  };

  failures = lib.mapAttrsToList (
    name: case: "  ${name}: got '${toString case.actual}', want '${toString case.expected}'"
  ) (lib.filterAttrs (_: case: case.actual != case.expected) cases);

  # Selecting a subset changes only this derivation, and it is symlinks.
  env = base.env { plugins = [ base.members.alpha ]; };
in
assert lib.assertMsg (failures == [ ]) ''
  lib/mk-package-set.nix does not hold the properties a package set claims:
  ${lib.concatStringsSep "\n" failures}'';
pkgs.runCommandLocal "package-set" { } ''
  test -d ${env}/plugins/resource-alpha-v1.2.3
  test -x ${env}/bin/pulumi-resource-alpha
  test -x ${env}/bin/pulumi

  if [ -e ${env}/plugins/resource-beta-v4.5.6 ]; then
    echo "package-set: env carries a plugin the selection excluded" >&2
    exit 1
  fi

  ${pkgs.jq}/bin/jq -e '.schemaVersion == 1 and .set.name == "fixture"' ${base.manifest} > /dev/null

  touch $out
''
