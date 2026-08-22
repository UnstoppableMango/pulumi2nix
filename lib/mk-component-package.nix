# Builds a source-based, multi-language component provider package and layers
# per-language SDK generation on top via with-generated-sdks.nix. The `schemaArgs`
# arg is kept separate from the top-level `<lang>Args` blocks because schema
# extraction and SDK packaging need independent npm dependency contexts.
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
