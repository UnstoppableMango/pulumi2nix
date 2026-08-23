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

  inherit (import ./fragments.nix { inherit lib; }) required;

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

  # Control over lib/narrow-sdk-src.nix, which hands each checked-in SDK only
  # the part of the shared provider tree it builds from. `null` keeps the
  # builder's own default; both are dropped by `toLangArgs` when left unset.
  # Not offered for generated SDKs: their source is codegen output, already
  # scoped to the one language.
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

  # Opt a checked-in language out of the committed `sdk/<lang>` tree and codegen
  # it from the declaration's own schema instead, via lib/with-generated-sdks.nix
  # (python excepted: mkTerraformBridgeProvider generates that one in place,
  # since with-generated-sdks.nix has no python builder to hand it to).
  #
  # Both default to `null` so `toLangArgs` drops them, leaving the builder's own
  # default and every existing declaration byte-identical.
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

  # Checked-in SDKs build from the provider repo's own tree, so they are the
  # ones `narrowing` applies to. `generation` is the escape hatch out of that
  # tree, offered here rather than under `generated` because it is a property of
  # an already-declared language, not a separate list of them.
  checkedInSdk = options: sdk (narrowing // generation // options);

  # `pulumi package gen-sdk` needs the target language's own host binary.
  languagePlugin = required types.package ''
    The `pulumi-language-<lang>` host used to run codegen, e.g.
    `pkgs.pulumiPackages.pulumi-go`. .NET has no nixpkgs build; use this
    repo's `pulumi2nix.pulumiLanguageDotnet`.
  '';

  # Both nodejs builders bundle their pruned `node_modules` into the output, so
  # both take the same escape hatch out of it. `null` leaves the builder's own
  # default of `[ "@pulumi/pulumi" ]`, dropped by `toLangArgs` when unset.
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
in
rec {
  # Languages whose SDK source is checked into the upstream provider repo under
  # `sdk/<lang>`, layered on by lib/with-sdks.nix.
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
        type = checkedInSdk { };
        default = null;
        description = ''
          Extra arguments for the python SDK. Unlike the other languages this
          does not select whether a python SDK is built: mkTerraformBridgeProvider
          always builds one, and lib/lang-arg-names.nix deliberately excludes
          `pythonArgs` from the generic dispatch. `generate` still selects where
          its source comes from, handled by that builder directly rather than by
          lib/with-generated-sdks.nix.
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
