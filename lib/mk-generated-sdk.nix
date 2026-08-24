# Deprecated: use `mkSdkSource` with a `schema`, which this now forwards to.
#
# Kept so callers written against the old name keep working; the schema
# producer is one of three `mkSdkSource` takes.
{ mkSdkSource }:
{
  schema,
  lang,
  languagePlugin,
  pname,
  version,
  schemaOverrides ? { },
  meta ? { },
  ...
}:
mkSdkSource {
  inherit
    schema
    lang
    languagePlugin
    pname
    version
    schemaOverrides
    meta
    ;
}
