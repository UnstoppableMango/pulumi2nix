# Normalizes one plugin, given either as a package or as an explicit
# `{ name, version, plugin }`, to the shape Pulumi's plugin cache is keyed by.
#
# A plain package (e.g. `pkgs.pulumiPackages.github`) carries both halves
# already: `meta.mainProgram` is `pulumi-resource-<name>`, which every
# `mkPulumiPackage`/`mkTerraformBridgeProvider`/`mkDynamicBridgeProvider` build
# sets, and `version` is the plugin version. `dir` is the directory name
# `~/.pulumi/plugins` uses, which is what makes a plugin findable at all.
{ lib }:
raw:
let
  normalized =
    if lib.isDerivation raw then
      {
        name = lib.removePrefix "pulumi-resource-" (
          raw.meta.mainProgram or (throw ''
            pulumi2nix: plugin package '${raw.name}' has no `meta.mainProgram`, so
            its plugin name can't be derived. Pass the explicit
            { name, version, plugin } form instead.
          '')
        );
        inherit (raw) version;
        plugin = "${raw}/bin";
      }
    else
      raw;
in
normalized // { dir = "resource-${normalized.name}-v${normalized.version}"; }
