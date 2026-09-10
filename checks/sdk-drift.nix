# mkSdkDriftCheck generates nothing: both sides are SDK source trees, so it is
# testable against the fixture provider rather than only against a real
# provider's gen tool.
{
  pkgs,
  mkSdkDriftCheck,
}:
let
  fixture = ./fixtures/provider;

  # What a regenerated SDK would look like after a resource change landed
  # without the committed tree being regenerated with it.
  drifted = pkgs.runCommandLocal "sdk-drift-fixture-drifted" { } ''
    mkdir -p $out/sdk/nodejs
    cp -r ${fixture}/sdk/nodejs/. $out/sdk/nodejs/
    chmod -R u+w $out/sdk/nodejs
    echo "export const addedResource = true;" >> $out/sdk/nodejs/index.ts
  '';

  # Differs only in a file the check excludes by default, so it must still pass.
  regenerated = pkgs.runCommandLocal "sdk-drift-fixture-regenerated" { } ''
    mkdir -p $out/sdk/nodejs
    cp -r ${fixture}/sdk/nodejs/. $out/sdk/nodejs/
    chmod -R u+w $out/sdk/nodejs
    echo '{}' > $out/sdk/nodejs/package-lock.json
  '';

  check =
    name: against:
    mkSdkDriftCheck {
      pname = "sdk-drift-${name}";
      lang = "nodejs";
      committed = fixture;
      inherit against;
    };

  failed = pkgs.testers.testBuildFailure (check "drifted" drifted);

  reportsDrift = pkgs.runCommandLocal "sdk-drift-reports" { } ''
    log=${failed}/testBuildFailure.log

    grep -q "does not match what this provider generates" "$log"
    grep -q "addedResource" "$log"

    touch $out
  '';

  reportsMissingTree = pkgs.runCommandLocal "sdk-drift-missing-tree" { } ''
    log=${
      pkgs.testers.testBuildFailure (mkSdkDriftCheck {
        pname = "sdk-drift-missing";
        lang = "python";
        committed = fixture;
        against = drifted;
      })
    }/testBuildFailure.log

    grep -q "no committed sdk/python to compare against" "$log"

    touch $out
  '';
in
pkgs.linkFarmFromDrvs "sdk-drift" [
  (check "identical" fixture)
  (check "excluded-only" regenerated)
  reportsDrift
  reportsMissingTree
]
