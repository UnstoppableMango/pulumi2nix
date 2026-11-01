{
  lib,
  stdenv,
  fetchYarnDeps,
  yarnConfigHook,
  yarnBuildHook,
  yarnInstallHook,
  nodejs,
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

    # As in npm.nix: `npm pack` of the installed package, as installed. The
    # `omitDeps` cleanup below only deletes `node_modules` entries, which `npm
    # pack` leaves out anyway, and the package.json keeps `@pulumi/pulumi`.
    outputs = [
      "out"
      "tarball"
    ];

    nativeBuildInputs = [
      yarnConfigHook
      yarnBuildHook
      yarnInstallHook
      nodejs
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

    postInstall = ''
      pkgName=$(node -p "require('./package.json').name")
      mkdir -p "$tarball"
      # npm's default cache lives under HOME, which the sandbox leaves unwritable.
      npm_config_cache="$TMPDIR/npm-cache" npm pack "$out/lib/node_modules/$pkgName" \
        --ignore-scripts --pack-destination "$tarball"
    ''
    + lib.optionalString (omitDeps != [ ]) ''
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
