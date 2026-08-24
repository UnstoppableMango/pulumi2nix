# Extracts schema.json from a source-based, multi-language component provider by
# shelling out to `pulumi package get-schema`, which runs the source itself
# rather than a separate `cmd/pulumi-gen-<name>` tool. For nodejs, `get-schema`
# runs the install itself, so dependencies have to be resolvable offline by the
# time `buildPhase` starts, via either an npm cache plus a writable
# package-lock.json or a yarn offline cache; which one applies follows from the
# lockfile pair supplied, the same split that separates `lib/sdks/npm.nix` from
# `lib/sdks/yarn.nix`. `providerPlugins` pre-seeds the plugin cache so
# components that import another provider's SDK don't need network access
# during the build.
{
  lib,
  stdenv,
  nodejs,
  npmHooks,
  fetchNpmDeps,
  fetchYarnDeps,
  yarnConfigHook,
  pulumi,
}:
{
  src,
  languagePlugin,
  lockFile ? null,
  npmDepsHash ? null,
  yarnLockFile ? null,
  yarnDepsHash ? null,
  pname,
  version,
  meta ? { },
  providerPlugins ? [ ],
  ...
}@args:
let
  useNpm = lockFile != null && npmDepsHash != null;
  useYarn = yarnLockFile != null && yarnDepsHash != null;

  rest = removeAttrs args [
    "lockFile"
    "npmDepsHash"
    "yarnLockFile"
    "yarnDepsHash"
    "languagePlugin"
    "providerPlugins"
  ];

  sourceRootArg = lib.optionalAttrs (rest ? sourceRoot) { inherit (rest) sourceRoot; };

  postPatch =
    if useNpm then
      ''
        cp ${lockFile} package-lock.json
        chmod +w package-lock.json
      ''
    else
      ''
        cp ${yarnLockFile} yarn.lock
        chmod +w yarn.lock
      '';

  # A plain package (e.g. `pkgs.pulumiPackages.github`) is normalized to the
  # explicit { name, version, plugin } shape by reading its own `version` and
  # its `meta.mainProgram` (`pulumi-resource-<name>`), which every
  # `mkTerraformBridgeProvider`/`mkDynamicBridgeProvider` build sets.
  normalizeProviderPlugin =
    p:
    if lib.isDerivation p then
      {
        name =
          lib.removePrefix "pulumi-resource-"
            (p.meta.mainProgram or (throw ''
              mk-component-schema: providerPlugins package '${p.name}' has no
              `meta.mainProgram` set, so its plugin name can't be derived. Pass the
              explicit { name, version, plugin } form instead.
            ''));
        version = p.version;
        plugin = "${p}/bin";
      }
    else
      p;

  seedProviderPlugins = lib.concatMapStringsSep "\n" (
    raw:
    let
      p = normalizeProviderPlugin raw;
    in
    ''
      mkdir -p "$HOME/.pulumi/plugins/resource-${p.name}-v${p.version}"
      cp -r ${p.plugin}/. "$HOME/.pulumi/plugins/resource-${p.name}-v${p.version}/"
    ''
  ) providerPlugins;

  npmAttrs = {
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
  };

  yarnAttrs = {
    yarnOfflineCache = fetchYarnDeps {
      yarnLock = yarnLockFile;
      hash = yarnDepsHash;
    };

    nativeBuildInputs = [
      nodejs
      yarnConfigHook
      pulumi
      languagePlugin
    ];
  };

  installEnv =
    if useNpm then
      ''
        export npm_config_offline=true
      ''
    else
      ''
        yarn config --offline set yarn-offline-mirror "$yarnOfflineCache"
      '';
in
lib.throwIf (useNpm == useYarn)
  ''
    mkComponentSchema: needs exactly one lockfile pair, since `pulumi package get-schema`
    runs the nodejs install itself and picks its package manager from the lockfile it
    finds. Pass either `lockFile` + `npmDepsHash` (npm) or `yarnLockFile` +
    `yarnDepsHash` (yarn classic), not both and not neither.
  ''
  (
    stdenv.mkDerivation (
      {
        pname = "${pname}-component-schema";
        inherit
          version
          meta
          src
          postPatch
          ;

        buildPhase = ''
          runHook preBuild

          export HOME=$TMPDIR
          ${installEnv}
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
      // (if useNpm then npmAttrs else yarnAttrs)
      // rest
    )
  )
