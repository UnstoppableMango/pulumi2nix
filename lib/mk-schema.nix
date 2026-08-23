{
  stdenv,
  buildGoModule,
  fetchProviderSource,
  srcName,
}:
# Builds only a provider's generated `schema.json`, skipping the resource
# provider binary and any SDKs. `schemaCommand` is the gen tool invocation
# that leaves a `schema.json` in the invocation's cwd - callers normally get
# one supplied by mkTerraformBridgeSchema or mkPulumiSchema rather than
# calling this directly.
#
# `src` defaults to fetchProviderSource's fetch of `owner`/`repo`/`rev`/`hash`
# (`rev` defaulting to `v${version}`); pass `src` to build from a local checkout
# or a different fetcher. Those three reach the fetch through `args` rather than
# as formals, since they are only forced by that default and a caller supplying
# `src` can omit them. `repo` is a formal either way: it also names the output.
{
  repo,
  version,
  src ? fetchProviderSource "mk-schema.nix" args,
  vendorHash,
  cmdGen,
  schemaCommand,
  extraLdflags ? [ ],
  env ? { },
  meta ? { },
  ...
}@args:
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
