{ mkSchema }:
# tfgen's "schema" language writes to `sdk/schema/schema.json` by default.
# `--out .` forces it to write `schema.json` into the cwd instead, matching
# the convention mkSchema expects.
args:
mkSchema (
  {
    schemaCommand = "${args.cmdGen} schema --out .";
  }
  // args
)
