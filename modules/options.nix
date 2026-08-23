# The eight `pulumi.*` option trees, one per public builder in lib/default.nix.
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

            # The attribute name is already the flake output name; don't make
            # source-based providers repeat it as `pname`.
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
    common
    upstream
    goCmds
    componentSource
    componentSchema
    ;

  # Base for the three repo-fetching schema builders.
  schemaBase =
    common
    // upstream
    // {
      inherit (goCmds) cmdGen;
    };

  # Suppresses the flattened `packages.<name>-schema`. Its main use is resolving
  # a collision with a separately declared schema-only build of the same name.
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

  # tfgen emits every language SDK itself, offline, from the same `provider/`
  # module the provider build already compiles, so a bridged provider can check
  # its committed `sdk/<lang>` against a freshly generated one. Nothing else
  # does: the SDK builds consume whatever is committed, stale or not.
  sdkDrift = {
    sdkDrift = mkOption {
      type = types.submodule {
        freeformType = types.attrsOf types.raw;

        options = {
          languages = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = ''
              tfgen languages whose committed `sdk/<lang>` is compared against a
              fresh `cmdGen <lang> --out` run, one `checks.<name>-sdk-<lang>-generated`
              each.

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

  # Base for the two repo-fetching provider builders. `cmdRes` and checked-in
  # SDK layering are what separate these from schemaBase.
  providerBase =
    schemaBase
    // exposeSchema
    // {
      inherit (goCmds) cmdRes;

      sdks = sdksOption sdkTypes.checkedIn ''
        Per-language SDKs built from the source checked into the upstream repo's
        `sdk/<lang>`, attached to `passthru.sdks`.
      '';
    };
in
{
  # -- schema-only builders ------------------------------------------------

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

  # -- package builders ----------------------------------------------------

  nativeProviders = tree (
    providerBase
    // {
      postConfigure = mkOption {
        type = types.lines;
        description = ''
          Required. The inherited terraform-bridge `postConfigure` assumes tfgen's
          `schema` subcommand; a native gen tool takes an explicit schema.json path
          plus `--version`, so relying on the default silently runs the wrong
          command instead of failing.
        '';
      };
    }
  );

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
