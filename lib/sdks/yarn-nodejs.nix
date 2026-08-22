{
  lib,
  stdenv,
  fetchYarnDeps,
  yarnConfigHook,
  yarnBuildHook,
  yarnInstallHook,
}:
# Companion to nodejs.nix for hand-written, non-codegen'd nodejs Pulumi
# packages (e.g. a plain component-resource library, not generated from a
# schema) that use yarn classic instead of npm - nodejs.nix's `lockFile`
# convention assumes a `package-lock.json`, which yarn-classic projects
# don't have (and regenerating one from `yarn.lock` corrupts its
# `resolved` URLs). This produces the same `$out/lib/node_modules/<pkgName>`
# output shape as nodejs.nix, so callers (and `with-sdks.nix`) don't need
# to care which one was used.
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

    sourceRoot = "${src.name}/sdk/nodejs";

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
  // (lib.removeAttrs args [
    "yarnLockFile"
    "yarnDepsHash"
  ])
)
