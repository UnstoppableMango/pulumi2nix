{
  lib,
  buildGoModule,
  fetchProviderSource,
  python3Packages,
  mkTerraformBridgeSchema,
  langArgNames,
  withSdks,
  srcName,
  narrowSdkSrc,
}:
let
  # Args this file consumes itself: the source-fetch inputs, the two `cmd/`
  # binary names, the ldflag list, and the flake module's SDK grouping key.
  # Each has already been read into `src`, `sourceRoot`, `subPackages` or
  # `ldflags` by the time the caller's attrset is forwarded, so letting them
  # through would only plant inert environment variables in the derivation.
  # That is not harmless: it forks the tfgen build in two (mk-schema.nix
  # builds the byte-identical binary from named formals, so its `pulumi-gen`
  # and the one below would otherwise differ only by these vars), and it makes
  # any change to them - documenting `owner`/`rev` alongside an explicit
  # `src`, respelling `cmdGen` - invalidate the provider and everything
  # downstream of it for no reason.
  controlArgs = [
    "cmd"
    "cmdGen"
    "cmdRes"
    "repo"
    "owner"
    "rev"
    "hash"
    "fetchSubmodules"
    "extraLdflags"
    "sdks"
  ];

  # Ported from nixpkgs' mk-pulumi-package.nix so this repo owns the build
  # recipe instead of reaching into a nixpkgs checkout at eval time.
  mkBasePackage =
    {
      src,
      cmd,
      extraLdflags,
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
      // removeAttrs args controlArgs
    );

  mkPythonPackage =
    {
      meta,
      pname,
      src,
      version,
      ...
    }@args:
    let
      # The derivation `pname` is lang-qualified so the provider and its SDKs
      # don't all land in the store under the same name. The Python
      # *distribution* name is a separate thing: it's what tfgen writes into
      # pyproject.toml, what pip installs, and what gets imported, so the checks
      # below key off `distName` rather than the derivation name.
      distName = args.distName or pname;
    in
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
            # runtime) is deprecated in setuptools v82.0.0 and later. Work around it by
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

            ${pip}/bin/pip show "${distName}" | grep "Version: ${version}" > /dev/null \
              || (echo "ERROR: Version substitution seems to be broken"; exit 1)

            runHook postCheck
          '';

          pythonImportsCheck = [
            (builtins.replaceStrings [ "-" ] [ "_" ] distName)
          ];

          # nixpkgs' pythonMetadataCheckPhase looks the installed distribution up
          # by the derivation `pname`, so a lang-qualified `pname` makes it fail
          # with `PackageNotFoundError` rather than a version mismatch. It only
          # compares .dist-info's version against `version`, which the `pip show`
          # check above already does against `distName`, so drop it rather than
          # give up the qualified name.
          dontCheckPythonMetadata = distName != pname;
        }
        // removeAttrs args (controlArgs ++ [ "distName" ])
      )
    ) { };
in
args:
let
  # Upstream mk-pulumi-package.nix has no defaults for rev/extraLdflags/env/
  # meta/fetchSubmodules, so normalize them here before forwarding.
  # Downstream consumers can default them independently for standalone use.
  #
  # `src` is resolved here rather than at each use so the gen tool, the resource
  # binary, the python SDK, withSdks and mkTerraformBridgeSchema all share one
  # source. It defaults to a fetch of `owner`/`repo`/`rev`/`hash`; pass `src` to
  # build from a local checkout or a different fetcher, in which case
  # `owner`/`hash` are never forced and can be omitted.
  args' = args // {
    rev = args.rev or "v${args.version}";
    fetchSubmodules = args.fetchSubmodules or false;
    extraLdflags = args.extraLdflags or [ ];
    env = args.env or { };
    meta = args.meta or { };
    src = args.src or (fetchProviderSource "mk-terraform-bridge-provider.nix" args);
  };

  base' = removeAttrs args' (langArgNames args');

  inherit (base') src;

  pythonArgs = base'.pythonArgs or { };

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

          # Only `sdk/python` of the shared tree, the same narrowing withSdks
          # applies to the other languages. See lib/narrow-sdk-src.nix.
          src = narrowSdkSrc.narrow "python" src pythonArgs;

          # Lang-qualified for the same reason as withSdks' layered SDKs: an
          # unqualified `repo` makes the provider and its SDKs indistinguishable
          # in store paths and build logs. Only `python3Packages`' interpreter
          # prefix kept this one apart before.
          pname = "${base'.repo}-sdk-python";

          # tfgen names the python distribution after the *Pulumi package*, not
          # the repo: `pulumi-resource-git` ships `sdk/python` as `pulumi_git`,
          # whatever the repo is called. Deriving this from `repo` only happens
          # to work for repos named `pulumi-<name>`, and gets both the
          # `pip show` check and the derived `pythonImportsCheck` wrong for
          # everything else. `sdks.python.pname` stays the escape hatch, since
          # `pythonArgs` is merged last and steers both names.
          distName = pythonArgs.pname or ("pulumi-" + lib.removePrefix "pulumi-resource-" base'.cmdRes);
        }
        // removeAttrs pythonArgs narrowSdkSrc.optionNames
      );
    }
    # `controlArgs` are stripped by mkBasePackage, which sees this whole merged
    # attrset; only `pythonArgs` has to go before the merge, so a caller's block
    # can't shadow the `passthru.sdks.python` already built from it.
    // (removeAttrs base' [ "pythonArgs" ])
  );

  withSdksResult = withSdks (args' // { inherit base; });
in
withSdksResult.overrideAttrs (old: {
  passthru = old.passthru // {
    schema = mkTerraformBridgeSchema args';
  };
})
