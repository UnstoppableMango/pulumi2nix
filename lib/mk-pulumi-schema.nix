{ mkSchema }:
# Native providers' gen tools take an explicit output path and version flag
# rather than tfgen's "schema" subcommand (see e.g.
# provider/cmd/pulumi-gen-command/main.go). Callers whose gen tool differs
# still override `schemaCommand` directly, same as `postConfigure` is
# overridden in the full provider builders.
args:
mkSchema (
  {
    schemaCommand = "${args.cmdGen} schema.json --version ${args.version}";
  }
  // args
)
