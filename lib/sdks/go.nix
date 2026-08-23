{
  buildGoModule,
  srcName,
}:
# Pulumi's go codegen emits an SDK whose module root is `sdk/go.mod`, one
# level above the importable package directory. Unlike nodejs/python, a Go
# SDK is consumed as module source rather than a compiled artifact: "build"
# just checks it compiles, and "install" copies the verified module source
# into $out.
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

    # No subPackages/buildPhase override needed: buildGoModule's default
    # buildPhase discovers every directory under sourceRoot containing .go
    # files and runs `go install`, which combined with the default doCheck
    # validates that the SDK compiles and type-checks. Sibling
    # sdk/{dotnet,java,nodejs,python} dirs contain no .go files, so this
    # discovery never visits them.

    # The default installPhase only copies $GOPATH/bin to $out, which is
    # empty here since there's no main package. Override it to copy the
    # verified module source instead, excluding sibling language dirs and
    # the ephemeral vendor/ dir.
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
