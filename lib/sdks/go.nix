{
  buildGoModule,
  srcName,
}:
{
  meta ? { },
  pname,
  src,
  version,
  vendorHash,
  ...
}@args:
buildGoModule (
  {
    inherit
      meta
      pname
      src
      version
      vendorHash
      ;

    sourceRoot = "${srcName src}/sdk";

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp go.mod go.sum $out/
      cp -r go $out/

      runHook postInstall
    '';
  }
  // args
)
