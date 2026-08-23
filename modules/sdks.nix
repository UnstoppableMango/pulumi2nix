# The `sdks.<lang>` option trees, plus the translation back to the
# `<lang>Args` convention the builders actually take.
#
# Why not just name the options `nodejsArgs`/`goArgs` directly: lib/lang-arg-names.nix
# selects language SDKs by the *string suffix* `Args` on any top-level key. Every
# submodule here carries `freeformType = attrsOf raw` as an escape hatch, so a
# freeform key that happened to end in `Args` would be silently read as a language.
# Nesting under `sdks` makes the set of languages explicit.
{ lib }:
let
  inherit (lib) mkOption types;

  required = type: description: mkOption { inherit type description; };

  # Per-SDK output controls. Consumed by flake-module.nix and stripped before
  # the remaining args reach a builder. `null` means "inherit the tree-wide
  # `pulumi.exposeSdks` / `pulumi.exposeSdkChecks` default".
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

  sdk =
    options:
    types.nullOr (
      types.submodule {
        freeformType = types.attrsOf types.raw;
        options = exposure // options;
      }
    );

  # `pulumi package gen-sdk` needs the target language's own host binary.
  languagePlugin = required types.package ''
    The `pulumi-language-<lang>` host used to run codegen, e.g.
    `pkgs.pulumiPackages.pulumi-go`. .NET has no nixpkgs build; use this
    repo's `pulumi2nix.pulumiLanguageDotnet`.
  '';

  nodejsCommon = {
    lockFile = required types.raw "`package-lock.json` for the SDK's dependencies.";
    npmDepsHash = required types.str "Hash of the SDK's npm dependencies.";
  };

  yarnCommon = {
    yarnLockFile = required types.raw "`yarn.lock` for the SDK's dependencies.";
    yarnDepsHash = required types.str "Hash of the SDK's yarn dependencies.";
  };

  dotnetCommon = {
    nugetDeps = required types.raw "NuGet lock file (`deps.json`) for the SDK.";
  };
in
rec {
  # Languages whose SDK source is checked into the upstream provider repo under
  # `sdk/<lang>`, layered on by lib/with-sdks.nix.
  checkedIn = types.submodule {
    options = {
      nodejs = mkOption {
        type = sdk nodejsCommon;
        default = null;
        description = "Build the repo's `sdk/nodejs` with npm.";
      };

      yarnNodejs = mkOption {
        type = sdk yarnCommon;
        default = null;
        description = ''
          Build the repo's `sdk/nodejs` with yarn classic instead of npm, for
          hand-written SDKs whose `yarn.lock` cannot be converted losslessly.
        '';
      };

      go = mkOption {
        type = sdk { vendorHash = required types.str "Vendor hash for the SDK module."; };
        default = null;
        description = "Build the repo's `sdk/go` module.";
      };

      dotnet = mkOption {
        type = sdk dotnetCommon;
        default = null;
        description = "Pack the repo's `sdk/dotnet` project as a .nupkg.";
      };

      python = mkOption {
        type = sdk { };
        default = null;
        description = ''
          Extra arguments for the python SDK. Unlike the other languages this
          does not select whether a python SDK is built: mkTerraformBridgeProvider
          always builds one, and lib/lang-arg-names.nix deliberately excludes
          `pythonArgs` from the generic dispatch.
        '';
      };
    };
  };

  # Languages whose SDK source is generated on demand from a schema.json by
  # lib/with-generated-sdks.nix. Each needs its own `languagePlugin`.
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
    };
  };

  # Module-only keys, never forwarded to a builder.
  exposureNames = builtins.attrNames exposure;

  # `{ go = {...}; }` -> `{ goArgs = {...}; }`, dropping unset languages, the
  # exposure flags, and any null-valued option default.
  toLangArgs =
    sdks:
    lib.mapAttrs' (lang: cfg: {
      name = "${lang}Args";
      value = lib.filterAttrs (_: v: v != null) (removeAttrs cfg (exposureNames ++ [ "_module" ]));
    }) (lib.filterAttrs (_: cfg: cfg != null) sdks);
}
