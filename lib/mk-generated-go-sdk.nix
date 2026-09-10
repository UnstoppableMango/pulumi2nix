{
  stdenv,
}:
{
  src,
  goMod,
  goSum,
  pname,
  version,
  meta ? { },
  ...
}:
stdenv.mkDerivation {
  name = "${pname}-generated-sdk-go-src";
  inherit version meta;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r ${src}/sdk $out/sdk
    chmod -R u+w $out/sdk
    cp ${goMod} $out/sdk/go.mod
    cp ${goSum} $out/sdk/go.sum

    runHook postInstall
  '';
}
