{
  buildGoModule,
}:
# Pulumi's go codegen emits an SDK whose module root is `sdk/go.mod` - one
# level above the importable package directory (`sdk/go/<pkg>/`). Unlike
# nodejs/python, a Go SDK isn't published as a compiled/installed artifact -
# it's consumed as module source (go.sum resolution or a `replace`
# directive). So there's no "build -> installed binary" step to mirror
# here: the "build" is a correctness check that the generated Go compiles,
# and the "install" is a verified copy of the module source (go.mod,
# go.sum, and the go/ package tree) into $out.
{
  meta,
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

    sourceRoot = "${src.name}/sdk";

    # No subPackages/buildPhase override needed: buildGoModule's default
    # buildPhase discovers every directory under sourceRoot containing .go
    # files (via `find`, not go list/module-boundary-aware) and runs `go
    # install` on each - for a non-main package (this SDK has none) that
    # just compiles and caches it, requiring no main package and erroring
    # on none. Combined with the default doCheck (go test over the same
    # discovered packages), this validates the SDK compiles and
    # type-checks without any override. Sibling sdk/{dotnet,java,nodejs,
    # python} dirs contain no .go files, so this discovery never visits
    # them.

    # The default installPhase only copies $GOPATH/bin to $out, empty here
    # since there's no main package. Override it to copy the verified
    # module source instead, excluding the sibling language dirs and the
    # ephemeral vendor/ dir buildGoModule populates during the build (a
    # downstream consumer resolves its own deps normally).
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
