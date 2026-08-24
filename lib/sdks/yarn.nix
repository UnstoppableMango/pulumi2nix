{
  lib,
  stdenv,
  fetchYarnDeps,
  yarnConfigHook,
  yarnBuildHook,
  yarnInstallHook,
  srcName,
}:
{
  meta ? { },
  pname,
  src,
  version,
  yarnLockFile,
  yarnDepsHash,
  omitDeps ? [ "@pulumi/pulumi" ],
  ...
}@args:
stdenv.mkDerivation (
  {
    inherit
      meta
      pname
      src
      version
      ;

    sourceRoot = "${srcName src}/sdk/nodejs";

    nativeBuildInputs = [
      yarnConfigHook
      yarnBuildHook
      yarnInstallHook
    ];

    yarnOfflineCache = fetchYarnDeps {
      yarnLock = yarnLockFile;
      hash = yarnDepsHash;
    };

    postPatch = ''
      cp ${yarnLockFile} yarn.lock
      sed -i \
        -e 's/"version": ".*"/"version": "${version}"/' \
        package.json
    '';

    postInstall = lib.optionalString (omitDeps != [ ]) ''
      shopt -s nullglob
      for nodeModules in "$out"/lib/node_modules/*/node_modules "$out"/lib/node_modules/@*/*/node_modules; do
        for dep in ${lib.escapeShellArgs omitDeps}; do
          rm -rf "$nodeModules/$dep"
        done
        find "$nodeModules" -maxdepth 1 -type d -empty -delete
        rmdir "$nodeModules" 2>/dev/null || true
      done
    '';
  }
  // lib.optionalAttrs (!(args ? yarnBuildScript)) { dontYarnBuild = true; }
  // (removeAttrs args [
    "yarnLockFile"
    "yarnDepsHash"
    "omitDeps"
  ])
)
