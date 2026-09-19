# The shell snippet that populates a Pulumi plugin cache from a list of plugins.
#
# Pulumi resolves a plugin by looking for `$PULUMI_HOME/plugins/resource-<name>-v<version>`,
# and writes to `$PULUMI_HOME` as it runs, so the cache can't be a store path
# directly: it has to be copied into a writable directory. Builds that need a
# provider available offline call this with `$HOME/.pulumi` as the root.
{ lib, pluginRef }:
{
  plugins,
  pulumiHome ? "$HOME/.pulumi",
}:
lib.concatMapStringsSep "\n" (
  raw:
  let
    p = pluginRef raw;
  in
  ''
    mkdir -p "${pulumiHome}/plugins/${p.dir}"
    cp -r ${p.plugin}/. "${pulumiHome}/plugins/${p.dir}/"
  ''
) plugins
