{
  stdenv,
  buildGoModule,
  fetchProviderSource,
  srcName,
}:
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
