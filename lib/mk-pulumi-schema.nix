{ mkSchema }:
# Native providers' gen tools take an explicit output path and version flag rather
# than tfgen's "schema" subcommand. Callers whose gen tool differs can
# override `schemaCommand` directly.
args:
mkSchema (
  {
    schemaCommand = "${args.cmdGen} schema.json --version ${args.version}";
  }
  // args
)
