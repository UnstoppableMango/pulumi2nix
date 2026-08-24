{
  lib,
  buildGoModule,
  fetchProviderSource,
  python3Packages,
  mkSdkDriftCheck,
  mkTerraformBridgeSchema,
  mkGeneratedSdk,
  langArgNames,
  withSdks,
  withGeneratedSdks,
  srcName,
  narrowSdkSrc,
}:
let
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
      distName = args.distName or pname;
    in
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
      // removeAttrs args (controlArgs ++ [ "distName" ])
    );
in
args:
let
  sdkDrift = args.sdkDrift or { };

  args' = removeAttrs args [ "sdkDrift" ] // {
    extraLdflags = args.extraLdflags or [ ];
    env = args.env or { };
    meta = args.meta or { };
    src = args.src or (fetchProviderSource "mk-terraform-bridge-provider.nix" args);
  };

  base' = removeAttrs args' (langArgNames args');

  inherit (base') src;

  pythonArgs = base'.pythonArgs or { };

  schema = mkTerraformBridgeSchema args';

  generates = name: args'.${name}.generate or false;
  langNames = langArgNames args';
  generatedNames = lib.filter generates langNames;

  forwarded = name: removeAttrs args'.${name} ([ "generate" ] ++ narrowSdkSrc.optionNames);

  generatedArgs = lib.genAttrs generatedNames (
    name: { pname = "${base'.repo}-sdk-${lib.removeSuffix "Args" name}"; } // forwarded name
  );

  checkedInArgs =
    removeAttrs args' generatedNames
    // lib.genAttrs (lib.filter (name: !generates name) langNames) (
      name: removeAttrs args'.${name} [ "generate" ]
    );

  missingPlugins = lib.filter (name: !(args'.${name} ? languagePlugin)) (
    generatedNames ++ lib.optional (pythonArgs.generate or false) "pythonArgs"
  );

  requirePlugins = lib.throwIf (missingPlugins != [ ]) ''
    mkTerraformBridgeProvider: ${lib.concatStringsSep ", " missingPlugins} set `generate`
    without a `languagePlugin`.

    Generating an SDK runs `pulumi package gen-sdk --language <lang>`, which needs that
    language's own host binary on PATH: `pkgs.pulumiPackages.pulumi-{nodejs,python,go}`,
    or this repo's `pulumiLanguageDotnet` for .NET, which nixpkgs has no build for.
    Set `<lang>Args.languagePlugin` (`sdks.<lang>.languagePlugin` in the flake module),
    or drop `generate` to keep building the repo's committed `sdk/<lang>`.
  '';

  pythonSrc =
    if pythonArgs.generate or false then
      mkGeneratedSdk {
        inherit schema;
        inherit (base') version meta;
        inherit (pythonArgs) languagePlugin;

        lang = "python";
        pname = base'.repo;
      }
    else
      narrowSdkSrc.narrow "python" src pythonArgs;

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

          src = pythonSrc;

          pname = "${base'.repo}-sdk-python";

          distName = pythonArgs.pname or ("pulumi-" + lib.removePrefix "pulumi-resource-" base'.cmdRes);
        }
        // removeAttrs pythonArgs (
          narrowSdkSrc.optionNames
          ++ [
            "generate"
            "languagePlugin"
          ]
        )
      );
    }
    // (removeAttrs base' [ "pythonArgs" ])
  );

  langs = sdkDrift.languages or [ ];
  driftLangs = if lib.isList langs then lib.genAttrs langs (_: { }) else langs;

  sdkDriftChecks = lib.mapAttrs (
    lang: langArgs:
    mkSdkDriftCheck (
      {
        inherit lang src;
        inherit (base') version meta cmdGen;

        pname = base'.repo;
        pulumiGen = pulumi-gen;
      }
      // removeAttrs sdkDrift [ "languages" ]
      // langArgs
    )
  ) driftLangs;

  withSdksResult = withSdks (checkedInArgs // { inherit base; });

  layered = withGeneratedSdks (
    generatedArgs
    // {
      inherit schema;
      inherit (base') version meta;

      base = withSdksResult;
      pname = base'.repo;
    }
  );
in
requirePlugins (
  layered.overrideAttrs (old: {
    passthru = old.passthru // {
      inherit sdkDriftChecks schema;
    };
  })
)
