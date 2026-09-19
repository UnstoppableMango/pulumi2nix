# Normalizes one plugin, given either as a package or as an explicit
# `{ name, version, plugin }`, to the shape Pulumi's plugin cache is keyed by.
#
# A package declares its plugin identity one of two ways. A compiled provider
# carries it in `meta.mainProgram` (`pulumi-resource-<name>`), which every
# `mkPulumiPackage`/`mkTerraformBridgeProvider`/`mkDynamicBridgeProvider` build
# sets, and serves the binary out of `$out/bin`. A component provider has no
# binary at all, so `mkComponentPlugin` states its name and subdirectory in
# `passthru.pulumiPlugin` instead.
#
# `dir` is the directory name `$PULUMI_HOME/plugins` uses, which is what makes a
# plugin findable at all.
{ lib }:
raw:
let
  declared = (raw.passthru or { }).pulumiPlugin or null;

  normalized =
    if !lib.isDerivation raw then
      raw
    else if declared != null then
      {
        inherit (declared) name;
        version = declared.version or raw.version;
        plugin = "${raw}/${declared.subdir or "bin"}";
      }
    else
      {
        name = lib.removePrefix "pulumi-resource-" (
          raw.meta.mainProgram or (throw ''
            pulumi2nix: plugin package '${raw.name}' declares neither
            `meta.mainProgram` nor `passthru.pulumiPlugin`, so its plugin name
            can't be derived. Pass the explicit { name, version, plugin } form
            instead.
          '')
        );
        inherit (raw) version;
        plugin = "${raw}/bin";
      };
in
normalized // { dir = "resource-${normalized.name}-v${normalized.version}"; }
