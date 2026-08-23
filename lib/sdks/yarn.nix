{
  lib,
  stdenv,
  fetchYarnDeps,
  yarnConfigHook,
  yarnBuildHook,
  yarnInstallHook,
  srcName,
}:
# Companion to npm.nix for hand-written, non-codegen'd nodejs packages
# that use yarn classic instead of npm, since regenerating a
# package-lock.json from yarn.lock corrupts its resolved URLs. Produces the
# same $out/lib/node_modules/<pkgName> output shape as npm.nix so callers
# don't need to care which one is used.
{
  meta ? { },
  pname,
  src,
  version,
  yarnLockFile,
  yarnDepsHash,
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
  }
  // lib.optionalAttrs (!(args ? yarnBuildScript)) { dontYarnBuild = true; }
  // (removeAttrs args [
    "yarnLockFile"
    "yarnDepsHash"
  ])
)
