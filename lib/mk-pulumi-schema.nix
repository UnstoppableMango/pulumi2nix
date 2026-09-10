{ mkSchema }:
args:
mkSchema (
  {
    schemaCommand = "${args.cmdGen} schema.json --version ${args.version}";
  }
  // args
)
