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

          ${python3Packages.pip}/bin/pip show "${distName}" | grep "Version: ${version}" > /dev/null \
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
    );
in
args:
let
  # Upstream mk-pulumi-package.nix has no defaults for extraLdflags/env/meta, so
  # normalize them here before forwarding.
  # Downstream consumers can default them independently for standalone use.
  #
  # `rev`/`fetchSubmodules` are deliberately *not* normalized: the only thing
  # that reads them is the fetch below, which sees the caller's raw `args` and
  # applies fetchProviderSource's own defaults. Normalizing them here would only
  # add attrs that `controlArgs` strips again.
  #
  # `src` is resolved here rather than at each use so the gen tool, the resource
  # binary, the python SDK, withSdks and mkTerraformBridgeSchema all share one
  # source. It defaults to a fetch of `owner`/`repo`/`rev`/`hash`; pass `src` to
  # build from a local checkout or a different fetcher, in which case
  # `owner`/`hash` are never forced and can be omitted.
  #
  # `sdkDrift` is consumed here alone, so it is stripped before `args'` rather
  # than at each forwarding site.
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

  # Built here rather than inside the final `passthru` so the generated SDKs
  # below and `passthru.schema` are the same derivation, not two byte-identical
  # ones evaluated from the same args.
  schema = mkTerraformBridgeSchema args';

  # A per-language `generate` splits the `<lang>Args` blocks between the two
  # layerers: `false` (the default) keeps reading the repo's committed
  # `sdk/<lang>`, `true` codegens that language from the schema above instead,
  # so a greenfield provider can drop its `sdk/` tree and the Makefile that
  # regenerates it.
  #
  # KNOWN LIMITATION. Generating goes straight to `pulumi package gen-sdk`,
  # which is where a current tfgen ends up anyway - `pkg/tfgen`'s `emitSDK`
  # delegates to that same command - but it is *only* that step. tfgen's
  # per-language overlays (`info.JavaScript.Overlay`, `info.Golang.Overlay`,
  # ...) are files the provider's own `resources.go` splices in around codegen;
  # nothing about them reaches the schema, so nothing here can replay them. A
  # provider that ships overlays has to keep its committed tree and guard it
  # with `sdkDrift` instead. See the README.
  generates = name: args'.${name}.generate or false;
  langNames = langArgNames args';
  generatedNames = lib.filter generates langNames;

  # `generate` selects a layerer, it is not a builder argument, so it is
  # stripped from every block whichever way it was set. The narrowing options go
  # with it for a generated language: there is no shared repo tree left to cut
  # down, the source is codegen output already scoped to the one language.
  forwarded = name: removeAttrs args'.${name} ([ "generate" ] ++ narrowSdkSrc.optionNames);

  # Lang-qualified for the same reason withSdks does it, and spelled here
  # because with-generated-sdks.nix names its SDKs after the *package* (its
  # component-provider callers give the base derivation a distinct `-component`
  # pname, this builder does not). Merged first, so a caller's own `pname` wins.
  generatedArgs = lib.genAttrs generatedNames (
    name: { pname = "${base'.repo}-sdk-${lib.removeSuffix "Args" name}"; } // forwarded name
  );

  checkedInArgs =
    removeAttrs args' generatedNames
    // lib.genAttrs (lib.filter (name: !generates name) langNames) (
      name: removeAttrs args'.${name} [ "generate" ]
    );

  # Both consumers pull `languagePlugin` straight out of the language's block
  # (`inherit (langArgs) languagePlugin` in with-generated-sdks.nix, a named
  # formal in mk-generated-sdk.nix), so omitting it surfaces as a bare
  # `attribute 'languagePlugin' missing` pointing at a file the caller never
  # wrote. Name the language and say what to do about it instead.
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

  # Python is the one language with-generated-sdks.nix refuses - it has no
  # registered builder there, only the upstream nixpkgs one this file delegates
  # to - and also the one this builder always builds, so `generate` is honoured
  # in place: hand mkGeneratedSdk's output to the same mkPythonPackage instead
  # of the narrowed repo tree. `srcName` reads the generated derivation's
  # `.name`, so `sourceRoot` resolves to `<repo>-generated-sdk-python/sdk/python`,
  # which is exactly where `gen-sdk --out $out/sdk` writes.
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

          # Only `sdk/python` of the shared tree, the same narrowing withSdks
          # applies to the other languages (see lib/narrow-sdk-src.nix), unless
          # `pythonArgs.generate` swapped the tree out for codegen output.
          src = pythonSrc;

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
        // removeAttrs pythonArgs (
          narrowSdkSrc.optionNames
          ++ [
            "generate"
            "languagePlugin"
          ]
        )
      );
    }
    # `controlArgs` are stripped by mkBasePackage, which sees this whole merged
    # attrset; only `pythonArgs` has to go before the merge, so a caller's block
    # can't shadow the `passthru.sdks.python` already built from it.
    // (removeAttrs base' [ "pythonArgs" ])
  );

  # A drift check per language re-runs `pulumi-gen`, the binary this build
  # already compiles, rather than standing up a second toolchain. Opt-in via
  # `sdkDrift.languages`: not every provider repo commits an `sdk/` tree, and a
  # check that cannot find one should not be the default.
  #
  # `languages` is a list on a pre-delegation bridge, where tfgen codegens every
  # language in-process and the check needs nothing but the gen tool. A current
  # bridge shells out to `pulumi package gen-sdk`, so those providers give an
  # attrset instead and name a `languagePlugin` per language. Both spellings
  # normalize to the same attrset here; see lib/mk-sdk-drift-check.nix for why
  # the two eras cannot be told apart from inside the build.
  langs = sdkDrift.languages or [ ];
  driftLangs = if lib.isList langs then lib.genAttrs langs (_: { }) else langs;

  # Per-language attrs land last so a language that needs its own `exclude` /
  # `extraExclude` (dotnet's `logo.png`, say) overrides the block shared by all
  # of them rather than being overridden by it.
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

  # The two layerers chain rather than compete: each one *overrides*
  # `passthru.sdks` onto whatever the derivation beneath it already carries, so
  # a provider that generates one language and commits another ends up with both
  # (and python, attached by `base` itself, survives either way).
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
