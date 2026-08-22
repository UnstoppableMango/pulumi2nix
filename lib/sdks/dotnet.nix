{
  buildDotnetModule,
}:
{
  meta ? { },
  pname,
  src,
  version,
  nugetDeps,
  ...
}@args:
buildDotnetModule (
  {
    inherit
      meta
      pname
      src
      version
      nugetDeps
      ;

    sourceRoot = "${src.name}/sdk/dotnet";

    # Pulumi's dotnet codegen leaves exactly one .csproj per SDK with no
    # version.txt (embedded as a resource, referenced but not generated) -
    # upstream's own Makefile writes it right before `dotnet build`. Mirror
    # that; leave projectFile unset so dotnet's own single-project
    # auto-discovery finds the one .csproj in sourceRoot.
    postPatch = ''
      echo -n "${version}" > version.txt
    '';

    # This SDK is a pure library (no entry point) whose .csproj already
    # sets GeneratePackageOnBuild - pack it as a .nupkg instead of
    # publishing a meaningless framework-dependent binary output.
    dontPublish = true;
    packNupkg = true;
  }
  // args
)
