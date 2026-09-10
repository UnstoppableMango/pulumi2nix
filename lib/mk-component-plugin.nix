# Builds a component provider's plugin: the source tree plus its
# `PulumiPlugin.yaml`, which together *are* the plugin. This shape has no
# compiled `pulumi-resource-<name>` binary, so there is nothing to build, only
# a tree to validate and install.
{
  lib,
  stdenv,
}:
{
  pname,
  version,
  src,
  meta ? { },

  # Attached as `passthru.schema` when the caller has one, so a component
  # plugin carries its schema the same way a provider binary does.
  schema ? null,
  ...
}@args:
stdenv.mkDerivation (
  {
    pname = "${pname}-component";
    inherit version meta src;

    dontBuild = true;

    installPhase = ''
      runHook preInstall

      if [ ! -f PulumiPlugin.yaml ]; then
        echo "mk-component-plugin.nix: expected PulumiPlugin.yaml at the component provider root" >&2
        exit 1
      fi

      mkdir -p $out
      cp -r . $out/

      runHook postInstall
    '';
  }
  // removeAttrs args [
    "schema"
    "pname"
  ]
  // lib.optionalAttrs (schema != null) { passthru.schema = schema; }
)
