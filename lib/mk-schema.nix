{
  stdenv,
  buildGoModule,
  fetchFromGitHub,
}:
# Builds only a provider's generated `schema.json`, skipping the resource
# provider binary and any SDKs. `schemaCommand` is the gen tool invocation
# that leaves a `schema.json` in the invocation's cwd - callers normally get
# one supplied by mkTerraformBridgeSchema or mkPulumiSchema rather than
# calling this directly.
{
  owner,
  repo,
  rev ? "v${version}",
  version,
  hash,
  vendorHash,
  cmdGen,
  schemaCommand,
  extraLdflags ? [ ],
  env ? { },
  fetchSubmodules ? false,
  meta ? { },
  ...
}:
let
  src = fetchFromGitHub {
    name = "source-${repo}-${rev}";
    inherit
      owner
      repo
      rev
      hash
      fetchSubmodules
      ;
  };

  pulumi-gen = buildGoModule {
    pname = cmdGen;
    inherit
      src
      version
      vendorHash
      env
      ;
    sourceRoot = "${src.name}/provider";
    subPackages = [ "cmd/${cmdGen}" ];
    doCheck = false;
    ldflags = [
      "-s"
      "-w"
    ]
    ++ extraLdflags;
  };
in
stdenv.mkDerivation {
  pname = "${repo}-schema";
  inherit src version meta;

  sourceRoot = "${src.name}/provider";
  nativeBuildInputs = [ pulumi-gen ];

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
}
