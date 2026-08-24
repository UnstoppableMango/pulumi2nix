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

    postPatch = ''
      echo -n "${version}" > version.txt
    '';

    dontPublish = true;
    packNupkg = true;
  }
  // args
)
