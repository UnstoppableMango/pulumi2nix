{ mkSchema }:
# tfgen's "schema" language writes to `sdk/schema/schema.json` by default
# (see pkg/tfgen/generate.go's `defaultOutDir` fallback); `--out .` forces
# it to write `schema.json` directly into the cwd instead, matching the
# convention mkSchema expects.
args:
mkSchema (
  {
    schemaCommand = "${args.cmdGen} schema --out .";
  }
  // args
)
