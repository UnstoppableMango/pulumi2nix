# Assembles a selection of plugins into the two shapes a Pulumi program can
# consume them in. Both are symlink trees over packages that are already built,
# so this derivation is what absorbs the combinatorics: which plugins a consumer
# picked never enters any plugin's own hash, only this one's.
#
#   $out/plugins/resource-<name>-v<version>/   Pulumi's plugin cache layout.
#   $out/bin/                                  the plugin binaries, plus the
#                                              pinned CLI when one is given.
#
# `passthru.seedScript` copies `$out/plugins` into a writable
# `$PULUMI_HOME/plugins`, which is the route a sandboxed build has to take:
# Pulumi writes to `$PULUMI_HOME` as it runs, so it can't be a store path.
{
  lib,
  runCommandLocal,
  pluginRef,
  seedPlugins,
}:
{
  name ? "pulumi-env",
  plugins ? [ ],
  pulumi ? null,
  ...
}@args:
let
  refs = map pluginRef plugins;

  # A component plugin's tree has no `bin`, so it contributes a cache entry and
  # nothing to `$out/bin`. Only compiled providers are ambient-resolvable.
  binaries = lib.filter (p: lib.hasSuffix "/bin" p.plugin) refs;

  linkCacheEntries = lib.concatMapStringsSep "\n" (
    p: ''ln -s ${p.plugin} "$out/plugins/${p.dir}"''
  ) refs;

  linkBinaries = lib.concatMapStringsSep "\n" (p: ''
    for bin in ${p.plugin}/*; do
      ln -s "$bin" "$out/bin/$(basename "$bin")"
    done
  '') binaries;
in
runCommandLocal name
  (
    {
      passthru = {
        inherit plugins;
        pluginRefs = refs;
        seedScript = seedPlugins { inherit plugins; };
      };
    }
    // removeAttrs args [
      "name"
      "plugins"
      "pulumi"
    ]
  )
  # `ln -s` onto an existing name fails, and the build runs under `set -e`, so
  # two plugins claiming one cache entry or one binary name is an error here
  # rather than a silent pick at run time.
  ''
    mkdir -p "$out/plugins" "$out/bin"

    ${linkCacheEntries}
    ${linkBinaries}
    ${lib.optionalString (pulumi != null) ''ln -s ${lib.getExe pulumi} "$out/bin/pulumi"''}
  ''
