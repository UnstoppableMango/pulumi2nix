# Builds a Pulumi python SDK, whether its source is the repo's committed
# `sdk/python` or a generated tree.
#
# `distName` is the name the SDK actually distributes under, which follows the
# provider's plugin name rather than the repo's: `pulumi-resource-random` gives
# `pulumi-random`, whatever the surrounding derivation is called. It drives
# `pythonImportsCheck` (dashes to underscores) and, when it differs from
# `pname`, disables nixpkgs' metadata name check.
{
  python3Packages,
  srcName,
}:
{
  pname,
  version,
  src,
  meta ? { },
  distName ? pname,
  ...
}@args:
python3Packages.buildPythonPackage (
  {
    inherit
      pname
      meta
      src
      version
      ;

    pyproject = true;

    sourceRoot = "${srcName src}/sdk/python";

    propagatedBuildInputs = with python3Packages; [
      parver
      pulumi
      semver
      setuptools
    ];

    postPatch = ''
      if [[ -e "pyproject.toml" ]]; then
        sed -i \
          -e 's/^  version = .*/  version = "${version}"/g' \
          pyproject.toml
      else
        sed -i \
           -e 's/^VERSION = .*/VERSION = "${version}"/g' \
           -e 's/^PLUGIN_VERSION = .*/PLUGIN_VERSION = "${version}"/g' \
           setup.py
      fi

      find . -name "_utilities.py" -exec sed -i \
        -e 's/import pkg_resources//g' \
        -e 's/pkg_resources.require(root_package)\[0\].version/"${version}"/g' \
        {} +
    '';

    checkPhase = ''
      runHook preCheck

      ${python3Packages.pip}/bin/pip show "${distName}" | grep "Version: ${version}" > /dev/null \
        || (echo "ERROR: Version substitution seems to be broken"; exit 1)

      runHook postCheck
    '';

    pythonImportsCheck = [
      (builtins.replaceStrings [ "-" ] [ "_" ] distName)
    ];

    dontCheckPythonMetadata = distName != pname;
  }
  // removeAttrs args [ "distName" ]
)
