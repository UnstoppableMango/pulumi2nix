# Extracts schema.json from a source-based, multi-language component provider by
# shelling out to `pulumi package get-schema`, which runs the source itself rather
# than a separate `cmd/pulumi-gen-<name>` tool. For nodejs, `get-schema` runs `npm
# install` itself, so it needs an offline npm cache and a writable package-lock.json
# (hence the `chmod +w`). `providerPlugins` pre-seeds the plugin cache so components
# that import another provider's SDK don't need network access during the build.
{
  lib,
  stdenv,
  nodejs,
  npmHooks,
  fetchNpmDeps,
  pulumi,
}:
{
  src,
  languagePlugin,
  lockFile,
  npmDepsHash,
  pname,
  version,
  meta ? { },
  # List of { name, version, plugin }, seeded into the plugin cache before get-schema runs.
  providerPlugins ? [ ],
  ...
}@args:
let
  # `sourceRoot` is not a formal: it is forwarded verbatim like every other
  # unrecognised arg, and read back out of `rest` for the one place that needs
  # it separately (the npm dep fetch, which unpacks the same tree).
  rest = removeAttrs args [
    "lockFile"
    "npmDepsHash"
    "languagePlugin"
    "providerPlugins"
  ];

  sourceRootArg = lib.optionalAttrs (rest ? sourceRoot) { inherit (rest) sourceRoot; };

  postPatch = ''
    cp ${lockFile} package-lock.json
    chmod +w package-lock.json
  '';

  seedProviderPlugins = lib.concatMapStringsSep "\n" (p: ''
    mkdir -p "$HOME/.pulumi/plugins/resource-${p.name}-v${p.version}"
    cp -r ${p.plugin}/. "$HOME/.pulumi/plugins/resource-${p.name}-v${p.version}/"
  '') providerPlugins;
in
stdenv.mkDerivation (
  {
    pname = "${pname}-component-schema";
    inherit
      version
      meta
      src
      postPatch
      ;

    npmDeps = fetchNpmDeps (
      {
        inherit src postPatch;
        hash = npmDepsHash;
      }
      // sourceRootArg
    );

    nativeBuildInputs = [
      nodejs
      npmHooks.npmConfigHook
      pulumi
      languagePlugin
    ];

    dontNpmBuild = true;

    buildPhase = ''
      runHook preBuild

      export HOME=$TMPDIR
      export npm_config_offline=true
      ${seedProviderPlugins}
      pulumi package get-schema . > schema.json

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp schema.json $out/schema.json

      runHook postInstall
    '';
  }
  // rest
)
