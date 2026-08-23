# Completes `mkGeneratedSdk`'s go output into a consumable module tree. `pulumi package
# gen-sdk --language go` emits only `.go` sources, never `go.mod`/`go.sum`: a module path
# is external convention that upstream provider repos maintain by hand, and populating a
# `require` block needs a real `go mod tidy` against the network, which a sandboxed
# derivation can't do. So the caller supplies both files, the same way `nodejsArgs` takes
# a `package-lock.json` and `dotnetArgs` a `deps.json`. See the README for how to
# regenerate them.
#
# The output name matters: `lib/sdks/go.nix` derives its `sourceRoot` from `src.name`.
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
