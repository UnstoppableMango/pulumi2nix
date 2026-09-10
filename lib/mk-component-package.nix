# Composes a component provider package:
#
#   mkComponentSchema -> mkComponentPlugin -> withSdks
#
# A component provider has no committed `sdk/<lang>` tree, so every SDK is
# generated from the extracted schema; `generate` is defaulted on rather than
# left to the caller.
{
  lib,
  langArgNames,
  mkComponentPlugin,
  mkComponentSchema,
  withSdks,
}:
{
  pname,
  version,
  src,
  meta ? { },
  schemaArgs,
  ...
}@args:
let
  langNames = langArgNames args;

  schema = mkComponentSchema (
    {
      inherit
        pname
        version
        meta
        src
        ;
    }
    // schemaArgs
  );

  plugin = mkComponentPlugin (
    removeAttrs args (
      langNames
      ++ [
        "schemaArgs"
        "sdks"
      ]
    )
    // {
      inherit
        pname
        version
        meta
        src
        schema
        ;
    }
  );

  langArgs = lib.genAttrs langNames (name: { generate = true; } // args.${name});
in
withSdks (
  langArgs
  // {
    base = plugin;
    inherit
      schema
      pname
      version
      meta
      ;
  }
)
