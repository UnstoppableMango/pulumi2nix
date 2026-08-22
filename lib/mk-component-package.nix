# Builds a source-based, multi-language component provider package (a
# folder with a PulumiPlugin.yaml - see mk-component-schema.nix) and
# layers per-language SDK generation on top via with-generated-sdks.nix.
#
# Unlike mk-pulumi-package.nix, there's no compiled `pulumi-resource-<name>`
# binary to build - the "build" step is just a validated copy of the
# source into $out, with schema extraction as the actual heavyweight step
# attached at passthru.schema. The `schemaArgs` arg is a nested attrset
# (`languagePlugin`, `lockFile`, `npmDepsHash`, ...) forwarded to
# mkComponentSchema, kept separate from the top-level `<lang>Args` blocks
# since schema extraction and SDK packaging need independent npm
# dependency contexts (the component's own package.json vs. gen-sdk's
# freshly generated one) despite using the same arg names. Named
# `schemaArgs` rather than `schema` to avoid colliding with the
# `passthru.schema` derivation this builder produces.
{
  stdenv,
  mkComponentSchema,
  withGeneratedSdks,
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
  schemaDrv = mkComponentSchema (
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

  base = stdenv.mkDerivation {
    pname = "${pname}-component";
    inherit version meta src;

    dontBuild = true;

    installPhase = ''
      runHook preInstall

      if [ ! -f PulumiPlugin.yaml ]; then
        echo "mk-component-package.nix: expected PulumiPlugin.yaml at the component provider root" >&2
        exit 1
      fi

      mkdir -p $out
      cp -r . $out/

      runHook postInstall
    '';

    passthru.schema = schemaDrv;
  };
in
withGeneratedSdks (
  (removeAttrs args [ "schemaArgs" ])
  // {
    inherit base;
    schema = schemaDrv;
  }
)
