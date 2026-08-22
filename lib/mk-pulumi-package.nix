{
  mkTerraformBridgeProvider,
  mkPulumiSchema,
}:
args:
(mkTerraformBridgeProvider args).overrideAttrs (old: {
  # mkPulumiPackage's native + SDK-layering use case gets the native gen-tool
  # schema convention, overriding the terraform-bridge one `mkTerraformBridgeProvider` attached.
  passthru = old.passthru // {
    schema = mkPulumiSchema args;
  };
})
