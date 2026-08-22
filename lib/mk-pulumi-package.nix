{
  langArgNames,
  mkTerraformBridgeProvider,
  mkPulumiSchema,
  withSdks,
}:
args@{ ... }:
let
  argNames = langArgNames args;
  base = mkTerraformBridgeProvider (removeAttrs args argNames);
  withSdksResult = withSdks (args // { inherit base; });
in
withSdksResult.overrideAttrs (old: {
  # mkPulumiPackage's native + SDK-layering use case gets the native gen-tool
  # schema convention, overriding the terraform-bridge one `base` attached.
  passthru = old.passthru // {
    schema = mkPulumiSchema args;
  };
})
