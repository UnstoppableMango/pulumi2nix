# Builds `schema.json` by running a provider repo's own gen tool.
#
# The tool itself is `mkGenTool`'s artifact, not this one's: pass `genTool` to
# reuse a build, or let the default construct it from the same arguments. Only
# `schemaCommand` differs between conventions, which is what `mkPulumiSchema`
# and `mkTerraformBridgeSchema` fill in.
{
  stdenv,
  fetchProviderSource,
  mkGenTool,
  srcName,
}:
{
  repo,
  version,
  src ? fetchProviderSource "mk-schema.nix" args,
  schemaCommand,
  meta ? { },
  ...
}@args:
let
  genTool = args.genTool or (mkGenTool (args // { inherit src; }));
in
stdenv.mkDerivation {
  pname = "${repo}-schema";
  inherit src version meta;

  sourceRoot = "${srcName src}/provider";
  nativeBuildInputs = [ genTool ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    pushd ..
    chmod u+w .
    ${schemaCommand}
    mkdir -p $out
    cp schema.json $out/schema.json
    popd

    runHook postInstall
  '';

  passthru = { inherit genTool; };
}
