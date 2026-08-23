{
  stdenv,
  buildGoModule,
  fetchFromGitHub,
  srcName,
}:
# Builds only a provider's generated `schema.json`, skipping the resource
# provider binary and any SDKs. `schemaCommand` is the gen tool invocation
# that leaves a `schema.json` in the invocation's cwd - callers normally get
# one supplied by mkTerraformBridgeSchema or mkPulumiSchema rather than
# calling this directly.
#
# `src` defaults to a fetch of `owner`/`repo`/`rev`/`hash`; pass it to build
# from a local checkout or a different fetcher. `owner`/`hash` are only forced
# by that default, so a caller supplying `src` can omit them. `repo`/`rev` are
# used for naming either way.
{
  owner ? throw "mk-schema.nix: `owner` is required unless `src` is supplied",
  repo,
  rev ? "v${version}",
  version,
  hash ? throw "mk-schema.nix: `hash` is required unless `src` is supplied",
  src ? fetchFromGitHub {
    name = "source-${repo}-${rev}";
    inherit
      owner
      repo
      rev
      hash
      fetchSubmodules
      ;
  },
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
  pulumi-gen = buildGoModule {
    pname = cmdGen;
    inherit
      src
      version
      vendorHash
      env
      ;
    sourceRoot = "${srcName src}/provider";
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

  sourceRoot = "${srcName src}/provider";
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
