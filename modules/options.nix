# The eight `pulumi.*` option trees, one per package recipe in lib/default.nix.
# The artifact builders underneath those recipes are reached through `lib`
# directly, not through an option tree.
#
# Every submodule carries `freeformType = types.attrsOf types.raw`: the builders
# forward unrecognised args verbatim into buildGoModule/stdenv.mkDerivation, and
# real packages depend on that (`postConfigure`, `__darwinAllowLocalNetworking`).
# The declared options document and typecheck the args the README covers; the
# freeform type keeps the escape hatch open.
{ lib }:
let
  inherit (lib) mkOption types;

  fragments = import ./fragments.nix { inherit lib; };
  sdkTypes = import ./sdks.nix { inherit lib; };

  tree =
    options:
    mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            freeformType = types.attrsOf types.raw;
            inherit options;

            config = lib.optionalAttrs (options ? pname) { pname = lib.mkDefault name; };
          }
        )
      );
      default = { };
    };

  sdksOption =
    type: description:
    mkOption {
      inherit type description;
      default = { };
    };

  inherit (fragments)
    optional
    common
    upstream
    goCmds
    componentSource
    componentSchema
    ;

  schemaBase =
    common
    // upstream
    // {
      inherit (goCmds) cmdGen;
    };

  exposeSchema = {
    exposeSchema = mkOption {
      type = types.nullOr types.bool;
      default = null;
      description = ''
        Emit `packages.<name>-schema` from this declaration's `passthru.schema`.
        `null` inherits `pulumi.exposeSchemas`.
      '';
    };
  };

  sdkDriftLanguage = types.submodule {
    freeformType = types.attrsOf types.raw;

    options.languagePlugin = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = ''
        The `pulumi-language-<lang>` host this language's codegen runs through,
        e.g. `pkgs.pulumiPackages.pulumi-nodejs`. .NET has no nixpkgs build; use
        this repo's `pulumi2nix.pulumiLanguageDotnet`.

        Required on a bridge that delegates codegen, ignored on one that does
        not. Setting it also puts the `pulumi` CLI on the check's PATH.
      '';
    };
  };

  sdkDrift = {
    sdkDrift = mkOption {
      type = types.submodule {
        freeformType = types.attrsOf types.raw;

        options = {
          languages = mkOption {
            type = types.either (types.listOf types.str) (types.attrsOf sdkDriftLanguage);
            default = [ ];
            description = ''
              tfgen languages whose committed `sdk/<lang>` is compared against a
              fresh `cmdGen <lang> --out` run, one `checks.<name>-sdk-<lang>-drift`
              each.

              Two shapes. A plain list is enough when the bridge's `emitSDK`
              codegens every language in-process and offline. A bridge that
              instead shells out to `pulumi package gen-sdk --language <lang>`
              needs those providers to pass an attrset and name a
              `languagePlugin` per language:

              ```nix
              sdkDrift.languages = {
                nodejs.languagePlugin = pkgs.pulumiPackages.pulumi-nodejs;
                dotnet = {
                  languagePlugin = pulumi2nix.pulumiLanguageDotnet;
                  extraExclude = [ "logo.png" ];
                };
              };
              ```

              Which shape a provider needs is left to the caller, deliberately:
              it follows from the bridge version in the provider's own
              `go.mod`, which nothing here can read at eval time. Naming a
              plugin is the declaration. Anything else set per language
              (`exclude`, `extraExclude`, `sdkPath`) overrides the surrounding
              block for that language alone.

              Empty by default: not every provider repo commits an `sdk/` tree,
              and a check with nothing to compare against would only ever fail.
            '';
          };

          exclude = mkOption {
            type = types.nullOr (types.listOf types.str);
            default = null;
            description = ''
              Basenames `diff -r` skips, replacing the builder's default of
              `package-lock.json`, `go.mod`, `go.sum`, `version.txt` - the files
              tfgen never emits, which are therefore committed by hand and would
              always read as drift. Use `extraExclude` to add to that default
              rather than restate it.
            '';
          };

          extraExclude = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Appended to `exclude`, whatever it ends up being.";
          };
        };
      };
      default = { };
      description = ''
        Drift checks for this provider's committed SDK trees. Off unless
        `languages` is non-empty.
      '';
    };
  };

  embedding = {
    embedSchema = mkOption {
      type = types.nullOr types.bool;
      default = null;
      description = ''
        Plant the built `schema.json` at `schemaPath` before the plugin build,
        and run `go generate cmd/<cmdRes>/main.go` over it.

        Defaults to true for a bridged provider, whose `generate.go` turns the
        planted file into the `schema-embed.json` that `main.go` embeds, and
        false for a native one, where a `pulumi-go-provider` binary serves its
        schema from Go structs and embeds nothing.
      '';
    };

    schemaPath = optional types.str ''
      Where the plugin build reads `schema.json` from, relative to the repo
      root. Defaults to `provider/cmd/<cmdRes>/schema.json`, which is where
      tfgen writes it and where `generate.go` looks for it.
    '';
  };

  providerBase =
    schemaBase
    // exposeSchema
    // embedding
    // {
      inherit (goCmds) cmdRes;

      sdks = sdksOption sdkTypes.checkedIn ''
        Per-language SDKs built from the source checked into the upstream repo's
        `sdk/<lang>`, attached to `passthru.sdks`.
      '';
    };
in
{
  schemas = tree (
    schemaBase
    // {
      schemaCommand = mkOption {
        type = types.str;
        description = ''
          The gen tool's own invocation, run with `cmdGen` on PATH and the
          working directory being where `schema.json` must land. Use this tree
          when a provider fits neither the tfgen nor the native convention.
        '';
      };
    }
  );

  nativeSchemas = tree schemaBase;

  terraformBridgeSchemas = tree schemaBase;

  componentSchemas = tree (common // componentSource // componentSchema);

  nativeProviders = tree providerBase;

  terraformBridgeProviders = tree (providerBase // sdkDrift);

  dynamicBridgeProviders = tree (
    (removeAttrs (common // upstream) [
      "owner"
      "repo"
    ])
    // {
      owner = mkOption {
        type = types.str;
        default = "pulumi";
        description = "GitHub owner of the repo holding the `dynamic` package.";
      };

      repo = mkOption {
        type = types.str;
        default = "pulumi-terraform-bridge";
        description = ''
          Where the `dynamic` package actually lives. `pulumi/pulumi-terraform-provider`
          only hosts releases built from it.
        '';
      };

      versionString = optional types.str ''
        What the built binary reports as its version, compiled into the
        `dynamic/version.version` ldflag. Defaults to `rev`.

        A SHA-pinned build needs this: `pulumi/pulumi-terraform-provider` only
        hosts docs and releases, and one of its releases names the
        `pulumi-terraform-bridge` *commit* it was generated from rather than a
        bridge tag. So the release-accurate pin is `rev = "<sha>"` with
        `versionString = "v1.1.3"`; leaving it unset would make the binary
        report the 40-character SHA to `pulumi plugin ls`.
      '';
    }
  );

  componentPackages = tree (
    common
    // componentSource
    // exposeSchema
    // {
      schemaArgs = mkOption {
        type = types.submodule {
          freeformType = types.attrsOf types.raw;
          options = componentSchema;
        };
        description = ''
          Schema extraction settings. Kept separate from `sdks` because schema
          extraction and SDK packaging need independent npm dependency contexts.
          `pname`, `version`, `src` and `meta` are supplied from the enclosing
          package and must not be repeated here.
        '';
      };

      sdks = sdksOption sdkTypes.generated ''
        Per-language SDKs generated on demand from the extracted schema, attached
        to `passthru.sdks`.

        `python` is unavailable here: unlike the provider builders there is no
        upstream `mkPythonPackage` to delegate to for a generated SDK tree.
      '';
    }
  );
}
