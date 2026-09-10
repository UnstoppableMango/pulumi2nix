# The `sdks.<lang>` option trees, plus the translation back to the
# `<lang>Args` convention the builders actually take. Not named `nodejsArgs`/
# `goArgs` directly because lib/lang-arg-names.nix selects language SDKs by the
# *string suffix* `Args` on any top-level key, and every submodule here carries
# `freeformType = attrsOf raw` as an escape hatch, so a freeform key ending in
# `Args` would be silently read as a language. Nesting under `sdks` makes the
# set of languages explicit.
{ lib }:
let
  inherit (lib) mkOption types;

  inherit (import ./fragments.nix { inherit lib; }) optional required;

  exposure = {
    exposePackage = mkOption {
      type = types.nullOr types.bool;
      default = null;
      description = "Emit `packages.<name>-sdk-<lang>` for this SDK.";
    };

    exposeCheck = mkOption {
      type = types.nullOr types.bool;
      default = null;
      description = ''
        Emit `checks.<name>-sdk-<lang>` for this SDK. Set to `false` for SDKs
        with a known-broken or prohibitively slow build, so `nix flake check`
        stays meaningful.
      '';
    };
  };

  narrowing = {
    narrowSrc = mkOption {
      type = types.nullOr types.bool;
      default = null;
      description = ''
        Narrow this SDK's `src` to the subtree it builds from (default: true),
        so an unrelated file change no longer rebuilds it. Set to `false` for a
        repo whose SDK build reads files elsewhere in the tree. Already a no-op
        when `src` is an unbuilt derivation, such as the default fetch.
      '';
    };

    srcPaths = mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
      description = ''
        Repo-relative paths making up this SDK's narrowed `src`, replacing the
        per-language default (e.g. `sdk/nodejs`, `README.md`, `LICENSE` for
        nodejs). Paths that do not exist are skipped rather than failing.
      '';
    };
  };

  generation = {
    generate = mkOption {
      type = types.nullOr types.bool;
      default = null;
      description = ''
        Generate this SDK from the provider's schema with
        `pulumi package gen-sdk` instead of building the repo's committed
        `sdk/<lang>` (default: false). Requires `languagePlugin`.

        gen-sdk emits language sources and nothing else, so the caller-supplied
        module files stay required exactly as they are for a checked-in tree:
        `lockFile`/`npmDepsHash` for nodejs, `goMod`/`goSum` (plus
        `importBasePath`) for go, `nugetDeps` for dotnet.

        This runs codegen against the schema alone, so tfgen's per-language
        overlays (`info.JavaScript.Overlay` and friends) are not applied. A
        provider that ships overlays should keep its committed tree and guard it
        with `sdkDrift` instead.

        `narrowSrc`/`srcPaths` do not apply when this is set: the source is
        codegen output, already scoped to the one language.
      '';
    };

    languagePlugin = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = ''
        The `pulumi-language-<lang>` host used to run codegen when `generate` is
        set, e.g. `pkgs.pulumiPackages.pulumi-go`. .NET has no nixpkgs build;
        use this repo's `pulumi2nix.pulumiLanguageDotnet`. Ignored otherwise.
      '';
    };
  };

  sdk =
    options:
    types.nullOr (
      types.submodule {
        freeformType = types.attrsOf types.raw;
        options = exposure // options;
      }
    );

  checkedInSdk = options: sdk (narrowing // generation // options);

  languagePlugin = required types.package ''
    The `pulumi-language-<lang>` host used to run codegen, e.g.
    `pkgs.pulumiPackages.pulumi-go`. .NET has no nixpkgs build; use this
    repo's `pulumi2nix.pulumiLanguageDotnet`.
  '';

  omitDeps = mkOption {
    type = types.nullOr (types.listOf types.str);
    default = null;
    description = ''
      Runtime dependencies this SDK's output does not carry a copy of
      (default: `[ "@pulumi/pulumi" ]`). `@pulumi/pulumi` has to be a singleton
      in the consuming process, and node and bun resolve through the realpath of
      a symlink, so an SDK carrying its own copy talks to a different runtime
      than the program that imported it. Set to `[ ]` to ship the whole pruned
      tree.
    '';
  };

  nodejsCommon = {
    inherit omitDeps;
    lockFile = required types.raw "`package-lock.json` for the SDK's dependencies.";
    npmDepsHash = required types.str "Hash of the SDK's npm dependencies.";
  };

  yarnCommon = {
    inherit omitDeps;
    yarnLockFile = required types.raw "`yarn.lock` for the SDK's dependencies.";
    yarnDepsHash = required types.str "Hash of the SDK's yarn dependencies.";
  };

  dotnetCommon = {
    nugetDeps = required types.raw "NuGet lock file (`deps.json`) for the SDK.";
  };

  pythonCommon = {
    distName = optional types.str ''
      The name the SDK distributes under, which follows the plugin name rather
      than the repo's: `pulumi-resource-random` gives `pulumi-random`, whatever
      the repo is called. Drives `pythonImportsCheck` (dashes to underscores)
      and the version check. Defaulted by the provider recipes; set it for an
      SDK that does not follow the convention.
    '';
  };
in
rec {
  checkedIn = types.submodule {
    options = {
      nodejs = mkOption {
        type = checkedInSdk nodejsCommon;
        default = null;
        description = "Build the repo's `sdk/nodejs` with npm.";
      };

      yarnNodejs = mkOption {
        type = checkedInSdk yarnCommon;
        default = null;
        description = ''
          Build the repo's `sdk/nodejs` with yarn classic instead of npm, for
          hand-written SDKs whose `yarn.lock` cannot be converted losslessly.
        '';
      };

      go = mkOption {
        type = checkedInSdk { vendorHash = required types.str "Vendor hash for the SDK module."; };
        default = null;
        description = "Build the repo's `sdk/go` module.";
      };

      dotnet = mkOption {
        type = checkedInSdk dotnetCommon;
        default = null;
        description = "Pack the repo's `sdk/dotnet` project as a .nupkg.";
      };

      python = mkOption {
        type = checkedInSdk pythonCommon;
        default = null;
        description = ''
          Build the repo's `sdk/python` distribution. Opt-in like every other
          language: declare it (`python = { }` is enough) to get one.
        '';
      };
    };
  };

  generated = types.submodule {
    options = {
      nodejs = mkOption {
        type = sdk ({ inherit languagePlugin; } // nodejsCommon);
        default = null;
        description = "Generate and build a nodejs SDK from the extracted schema.";
      };

      yarnNodejs = mkOption {
        type = sdk ({ inherit languagePlugin; } // yarnCommon);
        default = null;
        description = "As `nodejs`, but built with yarn classic.";
      };

      go = mkOption {
        type = sdk {
          inherit languagePlugin;

          vendorHash = required types.str "Vendor hash for the generated SDK module.";

          importBasePath = required types.str ''
            The schema's `language.go.importBasePath`. Without it codegen falls
            back to an `example.com/...` path and writes self-imports that do
            not match the directories it just created, so the SDK cannot compile.
          '';

          goMod = required types.raw ''
            `go.mod` for the generated SDK. `pulumi package gen-sdk --language go`
            emits only `.go` sources, so this comes from the caller. See the
            README's "Go module files" section for how to produce it.
          '';

          goSum = required types.raw "`go.sum` matching `goMod`.";
        };
        default = null;
        description = "Generate and build a go SDK from the extracted schema.";
      };

      dotnet = mkOption {
        type = sdk ({ inherit languagePlugin; } // dotnetCommon);
        default = null;
        description = "Generate and pack a .NET SDK from the extracted schema.";
      };

      python = mkOption {
        type = sdk ({ inherit languagePlugin; } // pythonCommon);
        default = null;
        description = "Generate and build a python SDK from the extracted schema.";
      };
    };
  };

  exposureNames = builtins.attrNames exposure;

  toLangArgs =
    sdks:
    lib.mapAttrs' (lang: cfg: {
      name = "${lang}Args";
      value = lib.filterAttrs (_: v: v != null) (removeAttrs cfg (exposureNames ++ [ "_module" ]));
    }) (lib.filterAttrs (_: cfg: cfg != null) sdks);
}
