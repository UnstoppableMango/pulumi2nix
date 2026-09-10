# A provider bridged from Terraform ahead of time: schema from tfgen's `schema`
# language, plugin binary embedding it.
#
# `embedSchema` plants the already-built `schema.json` at
# `provider/cmd/<cmdRes>/schema.json`, where the repo's own `generate.go` reads
# it to write the version-stamped `schema-embed.json` that `main.go` embeds.
# That replaces a second in-build gen tool run, so the schema is built once.
{ mkProviderPackage }:
args:
mkProviderPackage (
  {
    schemaCommand = "${args.cmdGen} schema --out .";
    embedSchema = true;
  }
  // args
)
