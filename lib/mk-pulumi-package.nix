{
  mkTerraformBridgeProvider,
  mkPulumiSchema,
}:
args:
assert
  (args ? postConfigure)
  || throw ''
    mkPulumiPackage: `postConfigure` must be supplied. mkPulumiPackage wraps
    nixpkgs' terraform-bridge provider builder, whose built-in postConfigure
    default assumes the tfgen convention (`$cmdGen schema; go generate
    cmd/$cmdRes/main.go`). Native providers' gen tools take a different
    invocation (an explicit schema.json path + --version flag, not a
    "schema" subcommand) - relying on the default silently runs the wrong
    schema-gen command instead of failing. Pass your own postConfigure (see
    examples/pulumi-command/default.nix).
  '';
(mkTerraformBridgeProvider args).overrideAttrs (old: {
  # mkPulumiPackage's native + SDK-layering use case gets the native gen-tool
  # schema convention, overriding the terraform-bridge one `mkTerraformBridgeProvider` attached.
  passthru = old.passthru // {
    schema = mkPulumiSchema args;
  };
})
