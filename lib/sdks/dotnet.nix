{
  buildDotnetModule,
  srcName,
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

    sourceRoot = "${srcName src}/sdk/dotnet";

    # Pulumi's dotnet codegen leaves exactly one .csproj per SDK with no
    # version.txt; upstream's Makefile writes it right before `dotnet build`,
    # so mirror that. Leave projectFile unset so dotnet's single-project
    # auto-discovery finds the .csproj in sourceRoot.
    postPatch = ''
      echo -n "${version}" > version.txt
    '';

    # This SDK is a pure library whose .csproj already sets
    # GeneratePackageOnBuild, so pack it as a .nupkg instead of publishing a
    # meaningless binary output.
    dontPublish = true;
    packNupkg = true;
  }
  // args
)
