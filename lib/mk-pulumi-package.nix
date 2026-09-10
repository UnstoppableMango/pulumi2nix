# A native provider: schema from `cmd/pulumi-gen-<name>`, which takes an
# explicit output path and a `--version` flag.
#
# The plugin binary gets no schema planted. A `pulumi-go-provider` provider
# serves its schema from Go structs at runtime and embeds nothing, which is why
# this preset needs no `postConfigure` of its own. A native provider that *does*
# embed one can set `embedSchema = true` (plus `schemaPath` where it differs
# from `provider/cmd/<cmdRes>/schema.json`).
{ mkProviderPackage }:
args:
mkProviderPackage (
  {
    schemaCommand = "${args.cmdGen} schema.json --version ${args.version}";
  }
  // args
)
