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
  # List of { name, version, plugin }, seeded into the plugin cache before get-schema runs.
  providerPlugins ? [ ],
  ...
}@args:
let
  useNpm = lockFile != null && npmDepsHash != null;
  useYarn = yarnLockFile != null && yarnDepsHash != null;

  # `sourceRoot` is not a formal: it is forwarded verbatim like every other
  # unrecognised arg, and read back out of `rest` for the one place that needs
  # it separately (the npm dep fetch, which unpacks the same tree).
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

  seedProviderPlugins = lib.concatMapStringsSep "\n" (p: ''
    mkdir -p "$HOME/.pulumi/plugins/resource-${p.name}-v${p.version}"
    cp -r ${p.plugin}/. "$HOME/.pulumi/plugins/resource-${p.name}-v${p.version}/"
  '') providerPlugins;

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

    # No yarnBuildHook/yarnInstallHook: this derivation only reads the tree to
    # answer `GetSchema`, it never packages it. yarnConfigHook alone matters,
    # since it runs in configurePhase and populates `node_modules` from the
    # offline cache before get-schema's own install looks for it.
    nativeBuildInputs = [
      nodejs
      yarnConfigHook
      pulumi
      languagePlugin
    ];
  };

  # Both branches re-establish offline resolution for the install `get-schema`
  # runs itself: a fresh `yarn install` / `npm install` in the language host's
  # own process, outside the nixpkgs hooks' control. npm reads
  # `npm_config_offline` straight out of the environment.
  #
  # yarn needs more: a populated `node_modules` alone is not enough, since
  # `pulumi-language-nodejs` runs a plain `yarn install` that re-resolves from
  # the lockfile and hits the network unless it finds the offline mirror.
  # yarnConfigHook wrote the `yarn-offline-mirror` setting to its own `$HOME`,
  # which the `HOME=$TMPDIR` the pulumi CLI needs then discards, so
  # re-pointing the new HOME at the same cache lets the install complete
  # offline with no `YARN_*` env var.
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
