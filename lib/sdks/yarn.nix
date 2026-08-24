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
  # As npm.nix's `omitDeps`, with one difference: yarn classic's own `prune` is
  # a stub pointing at `install`, and by the time yarnInstallHook has run there
  # is nothing left to re-resolve against. So the named packages are deleted
  # from the installed tree rather than pruned out of it; anything reachable
  # only through them stays behind as dead weight nothing resolves to.
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

    # yarnInstallHook derives the package directory from package.json with jq,
    # which isn't an input here, so find the installed tree by glob instead -
    # one pattern for a plain name, one for a scoped one.
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
