{
  lib,
  buildNpmPackage,
}:
# Pulumi's nodejs codegen always emits an SDK that compiles to `bin/` and is
# published from there once package.json and the license/readme are copied
# alongside the compiled output. This mirrors that convention, the same
# shape used by every provider's Node.js SDK.
{
  meta ? { },
  pname,
  src,
  version,
  lockFile,
  ...
}@args:
buildNpmPackage (
  {
    inherit
      meta
      pname
      src
      version
      ;

    sourceRoot = "${src.name}/sdk/nodejs";

    postPatch = ''
      cp ${lockFile} package-lock.json
      sed -i \
        -e 's/"version": ".*"/"version": "${version}"/' \
        package.json
    '';

    npmBuildScript = "build";

    postBuild = ''
      cp package.json bin/
      cp ../../README.md ../../LICENSE bin/ 2>/dev/null || true
    '';

    installPhase = ''
      runHook preInstall

      pkgName=$(node -p "require('./bin/package.json').name")
      packageOut="$out/lib/node_modules/$pkgName"
      mkdir -p "$packageOut"
      cp -r bin/. "$packageOut/"

      if [ -z "''${dontNpmPrune-}" ]; then
        npm prune --omit=dev --no-save
      fi
      cp -r node_modules "$packageOut/node_modules"

      runHook postInstall
    '';
  }
  // (lib.removeAttrs args [ "lockFile" ])
)
