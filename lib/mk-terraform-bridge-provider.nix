{
  buildGoModule,
  fetchFromGitHub,
  python3Packages,
  mkTerraformBridgeSchema,
  langArgNames,
  withSdks,
  srcName,
}:
let
  # Ported from nixpkgs' mk-pulumi-package.nix so this repo owns the build
  # recipe instead of reaching into a nixpkgs checkout at eval time.
  mkBasePackage =
    {
      pname,
      src,
      version,
      vendorHash,
      cmd,
      extraLdflags,
      env,
      ...
    }@args:
    buildGoModule (
      {
        sourceRoot = "${srcName src}/provider";

        subPackages = [ "cmd/${cmd}" ];

        doCheck = false;

        ldflags = [
          "-s"
          "-w"
        ]
        ++ extraLdflags;
      }
      // args
    );

  mkPythonPackage =
    {
      meta,
      pname,
      src,
      version,
      ...
    }@args:
    python3Packages.callPackage (
      {
        buildPythonPackage,
        parver,
        pip,
        pulumi,
        semver,
        setuptools,
      }:
      buildPythonPackage (
        {
          inherit
            pname
            meta
            src
            version
            ;
          pyproject = true;

          sourceRoot = "${srcName src}/sdk/python";

          propagatedBuildInputs = [
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

            # pkg_resources (used by Pulumi Python SDKs to find their version at
            # runtime) was deprecated from setuptools in v82.0.0. Work around it by
            # removing the import and patching the version in as a literal.
            find . -name "_utilities.py" -exec sed -i \
              -e 's/import pkg_resources//g' \
              -e 's/pkg_resources.require(root_package)\[0\].version/"${version}"/g' \
              {} +
          '';

          # Auto-generated; upstream does not have any tests.
          # Verify that the version substitution works
          checkPhase = ''
            runHook preCheck

            ${pip}/bin/pip show "${pname}" | grep "Version: ${version}" > /dev/null \
              || (echo "ERROR: Version substitution seems to be broken"; exit 1)

            runHook postCheck
          '';

          pythonImportsCheck = [
            (builtins.replaceStrings [ "-" ] [ "_" ] pname)
          ];
        }
        // args
      )
    ) { };
in
args@{ ... }:
let
  # Upstream mk-pulumi-package.nix has no defaults for rev/extraLdflags/env/
  # meta/fetchSubmodules, so normalize them here before forwarding.
  # Downstream consumers can still default them independently for standalone use.
  #
  # `src` is resolved here rather than at each use so the gen tool, the resource
  # binary, the python SDK, withSdks and mkTerraformBridgeSchema all share one
  # source. It defaults to a fetch of `owner`/`repo`/`rev`/`hash`; pass `src` to
  # build from a local checkout or a different fetcher, in which case
  # `owner`/`hash` are never forced and can be omitted.
  args' = args // {
    rev = rev';
    extraLdflags = args.extraLdflags or [ ];
    env = args.env or { };
    meta = args.meta or { };
    fetchSubmodules = fetchSubmodules';
    src = args.src or fetchedSrc;
  };
  rev' = args.rev or "v${args.version}";
  fetchSubmodules' = args.fetchSubmodules or false;

  fetchedSrc = fetchFromGitHub {
    name = "source-${args.repo}-${rev'}";
    owner =
      args.owner
        or (throw "mk-terraform-bridge-provider.nix: `owner` is required unless `src` is supplied");
    hash =
      args.hash
        or (throw "mk-terraform-bridge-provider.nix: `hash` is required unless `src` is supplied");
    inherit (args) repo;
    rev = rev';
    fetchSubmodules = fetchSubmodules';
  };

  argNames = langArgNames args';
  base' = removeAttrs args' argNames;

  inherit (base') src;

  pulumi-gen = mkBasePackage {
    inherit (base')
      version
      vendorHash
      extraLdflags
      env
      ;
    inherit src;

    cmd = base'.cmdGen;
    pname = base'.cmdGen;
  };

  base = mkBasePackage (
    {
      pname = base'.repo;
      inherit (base') env;
      inherit src;

      nativeBuildInputs = [
        pulumi-gen
      ];

      cmd = base'.cmdRes;

      postConfigure = ''
        pushd ..

        chmod +w sdk/
        ${base'.cmdGen} schema

        popd

        VERSION=v${base'.version} go generate cmd/${base'.cmdRes}/main.go
      '';

      passthru.sdks.python = mkPythonPackage (
        {
          inherit (base') meta version;
          inherit src;

          pname = base'.repo;
        }
        // (base'.pythonArgs or { })
      );
    }
    // (removeAttrs base' [ "pythonArgs" ])
  );

  withSdksResult = withSdks (args' // { inherit base; });
in
withSdksResult.overrideAttrs (old: {
  passthru = old.passthru // {
    schema = mkTerraformBridgeSchema args';
  };
})
