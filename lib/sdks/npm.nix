{
  lib,
  buildNpmPackage,
  srcName,
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
  # Runtime dependencies the output does not carry a copy of. `@pulumi/pulumi`
  # has to be a singleton in the consuming process, since its Node runtime
  # keeps the resource monitor address and config at module scope, and node
  # and bun both resolve through the realpath of a symlink, so an SDK carrying
  # its own copy talks to a different runtime than the program that imported
  # it. Set to `[ ]` to ship the whole pruned tree.
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
        # Only the build tree's package.json: the shipped copy was taken in
        # postBuild and still declares these, so what the output says about
        # itself stays upstream's. Dropping them here is what lets the prune
        # below take their transitive-only dependencies along with them.
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

      # An emptied scope directory (`@pulumi/`) is still a directory, so clear
      # those before asking whether any package is left. Testing for a directory
      # rather than for any entry at all is what keeps npm's own bookkeeping
      # file (`node_modules/.package-lock.json`) from passing for content: an
      # SDK whose only runtime dependency was omitted ships no node_modules.
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
