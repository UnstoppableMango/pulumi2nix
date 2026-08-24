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
