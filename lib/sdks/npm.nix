{
  lib,
  buildNpmPackage,
  srcName,
}:
{
  meta ? { },
  pname,
  src,
  version,
  lockFile,
  omitDeps ? [ "@pulumi/pulumi" ],
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

    sourceRoot = "${srcName src}/sdk/nodejs";

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

      ${lib.optionalString (omitDeps != [ ]) ''
        node -e '
          const fs = require("fs");
          const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
          for (const name of process.argv.slice(1)) delete (pkg.dependencies ?? {})[name];
          fs.writeFileSync("package.json", JSON.stringify(pkg, null, 2));
        ' ${lib.escapeShellArgs omitDeps}
      ''}

      if [ -z "''${dontNpmPrune-}" ]; then
        npm prune --omit=dev --no-save
      fi

      find node_modules -maxdepth 1 -type d -empty -delete
      if [ -n "$(find node_modules -mindepth 1 -maxdepth 1 -type d 2>/dev/null)" ]; then
        cp -r node_modules "$packageOut/node_modules"
      fi

      runHook postInstall
    '';
  }
  // (removeAttrs args [
    "lockFile"
    "omitDeps"
  ])
)
