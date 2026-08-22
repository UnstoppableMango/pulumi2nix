{
  stdenv,
  buildGoModule,
  fetchFromGitHub,
}:
# Builds only a provider's generated `schema.json`, skipping the resource
# provider binary and any SDKs. Works for both terraform-bridge providers
# (default `schemaCommand`, matching tfgen's `<cmdGen> schema` convention,
# which always writes a `schema.json` in the invocation's cwd) and native
# providers whose gen tool takes an explicit output path instead - callers
# override `schemaCommand` the same way `postConfigure` is overridden for
# those in the full provider builders.
{
  owner,
  repo,
  rev,
  version,
  hash,
  vendorHash,
  cmdGen,
  extraLdflags ? [ ],
  env ? { },
  fetchSubmodules ? false,
  # tfgen's "schema" language writes to `sdk/schema/schema.json` by default
  # (see pkg/tfgen/generate.go's `defaultOutDir` fallback); `--out .` forces
  # it to write `schema.json` directly into the cwd instead.
  schemaCommand ? "${cmdGen} schema --out .",
  meta,
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
