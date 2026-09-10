# The deprecated aliases forward to their replacements. Nothing in this repo
# calls them any more, so without this they would rot silently.
#
# Equality of `drvPath` is the assertion: the alias has to produce the same
# derivation the replacement does, not merely something that evaluates.
{
  lib,
  pkgs,
  p2n,
}:
let
  schema = pkgs.runCommandLocal "deprecated-aliases-schema" { } ''
    mkdir -p $out
    echo '{"name":"fake","version":"0.0.1"}' > $out/schema.json
  '';

  common = {
    pname = "fake";
    version = "0.0.1";
    lang = "nodejs";
    languagePlugin = pkgs.pulumiPackages.pulumi-nodejs;
  };

  # Never built, so the placeholder hash is never checked.
  nodejsArgs = {
    languagePlugin = pkgs.pulumiPackages.pulumi-nodejs;
    lockFile = "${schema}/schema.json";
    npmDepsHash = lib.fakeHash;
  };

  base = pkgs.runCommandLocal "deprecated-aliases-base" { } "touch $out";

  layerArgs = {
    inherit base schema nodejsArgs;
    pname = "fake";
    version = "0.0.1";
  };

  sdkOf = layered: layered.passthru.sdks.nodejs.drvPath;

  cases = [
    {
      name = "mkGeneratedSdk";
      alias = (p2n.mkGeneratedSdk ({ inherit schema; } // common)).drvPath;
      direct = (p2n.mkSdkSource ({ inherit schema; } // common)).drvPath;
    }
    {
      name = "withGeneratedSdks";
      alias = sdkOf (p2n.withGeneratedSdks layerArgs);
      direct = sdkOf (
        p2n.withSdks (
          layerArgs
          // {
            nodejsArgs = nodejsArgs // {
              generate = true;
            };
          }
        )
      );
    }
  ];

  mismatched = lib.filter (case: case.alias != case.direct) cases;
in
assert lib.assertMsg (mismatched == [ ]) (
  "deprecated aliases no longer match their replacements: "
  + lib.concatMapStringsSep ", " (case: "${case.name} (${case.alias} != ${case.direct})") mismatched
);
# mkGeneratedGoSdk forwards to nothing, so evaluating it to a derivation is the
# whole check.
assert lib.isDerivation (
  p2n.mkGeneratedGoSdk {
    pname = "fake";
    version = "0.0.1";
    src = schema;
    goMod = "${schema}/schema.json";
    goSum = "${schema}/schema.json";
  }
);
pkgs.runCommandLocal "deprecated-aliases" { } "touch $out"
