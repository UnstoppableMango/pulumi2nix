# Extracts schema.json from a source-based, multi-language component
# provider (a folder with a `PulumiPlugin.yaml` declaring `runtime`, e.g.
# a hand-written nodejs `ComponentResource` library like pulumi-components)
# by shelling out to `pulumi package get-schema`, which launches a
# `pulumi-language-<runtime>` host to run the source and serve the
# `GetSchema` RPC itself - unlike `mk-schema.nix`, there's no separate
# `cmd/pulumi-gen-<name>` tool to build; the source *is* the provider.
#
# For nodejs specifically (the only runtime exercised so far), `get-schema`
# runs `npm install` itself as part of resolving the program - this needs
# an offline npm dependency cache (`fetchNpmDeps`, the same mechanism
# `lib/sdks/nodejs.nix`/`buildNpmPackage` already use elsewhere in this
# repo) plus `npm_config_offline=true`, or it isn't hermetic. Requires a
# TypeScript entry point (`index.ts` in root/src, or `main`/`exports` in
# package.json pointing at one) - a plain `.js` `main` is not discovered.
#
# `npm install` also rewrites package-lock.json in place, so the copy
# staged in postPatch needs to be writable - `cp` from a nix store path
# preserves the source's read-only mode, hence the `chmod +w` below.
#
# A component that imports another provider's SDK (e.g. `@pulumi/github`)
# makes `get-schema` try to download that provider's resource plugin from
# get.pulumi.com, which the sandboxed build has no network access for.
# `providerPlugins` lets a caller seed `$HOME/.pulumi/plugins` with
# pre-fetched plugin derivations to avoid that.
{
  lib,
  stdenv,
  nodejs,
  npmHooks,
  fetchNpmDeps,
  pulumi,
}:
{
  src,
  languagePlugin,
  lockFile,
  npmDepsHash,
  pname,
  version,
  meta ? { },
  sourceRoot ? null,
  # List of { name, version, plugin } - plugin is a derivation whose
  # output directory holds an already-extracted pulumi-resource-<name>
  # plugin binary, seeded into the plugin cache before get-schema runs.
  providerPlugins ? [ ],
  ...
}@args:
let
  postPatch = ''
    cp ${lockFile} package-lock.json
    chmod +w package-lock.json
  '';

  seedProviderPlugins = lib.concatMapStringsSep "\n" (p: ''
    mkdir -p "$HOME/.pulumi/plugins/resource-${p.name}-v${p.version}"
    cp -r ${p.plugin}/. "$HOME/.pulumi/plugins/resource-${p.name}-v${p.version}/"
  '') providerPlugins;
in
stdenv.mkDerivation (
  {
    pname = "${pname}-component-schema";
    inherit
      version
      meta
      src
      postPatch
      ;

    npmDeps = fetchNpmDeps (
      {
        inherit src postPatch;
        hash = npmDepsHash;
      }
      // lib.optionalAttrs (sourceRoot != null) { inherit sourceRoot; }
    );

    nativeBuildInputs = [
      nodejs
      npmHooks.npmConfigHook
      pulumi
      languagePlugin
    ];

    dontNpmBuild = true;

    buildPhase = ''
      runHook preBuild

      export HOME=$TMPDIR
      export npm_config_offline=true
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
  // lib.optionalAttrs (sourceRoot != null) { inherit sourceRoot; }
  // (lib.removeAttrs args [
    "lockFile"
    "npmDepsHash"
    "languagePlugin"
    "sourceRoot"
    "providerPlugins"
  ])
)
