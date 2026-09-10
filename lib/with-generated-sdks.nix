# Deprecated: use `withSdks`, which now covers both SDK source routes.
#
# Kept so callers written against the old name keep working. The only
# difference is the default: every language here generates from `schema`.
{
  lib,
  langArgNames,
  withSdks,
}:
{
  base,
  schema,
  pname,
  version,
  meta ? { },
  ...
}@args:
let
  langArgs = lib.genAttrs (langArgNames args) (name: { generate = true; } // args.${name});
in
withSdks (
  langArgs
  // {
    inherit
      base
      schema
      pname
      version
      meta
      ;
  }
)
