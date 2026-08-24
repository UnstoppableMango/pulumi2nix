{ mkSchema }:
args:
mkSchema (
  {
    schemaCommand = "${args.cmdGen} schema --out .";
  }
  // args
)
