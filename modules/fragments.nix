{ lib }:
let
  inherit (lib) mkOption types;
in
rec {
  optional =
    type: description:
    mkOption {
      type = types.nullOr type;
      default = null;
      inherit description;
    };

  required =
    type: description:
    mkOption {
      inherit type description;
    };

  common = {
    version = required types.str ''
      Package version. Also the default `rev` (as `v''${version}`) for builders
      that fetch from GitHub.
    '';

    meta = mkOption {
      type = types.attrsOf types.raw;
      default = { };
      description = "Standard nixpkgs `meta` attrset, forwarded verbatim.";
    };
  };

  upstream = {
    owner = optional types.str ''
      GitHub owner for the default fetch. Required unless `src` is supplied.
    '';

    repo = required types.str ''
      GitHub repo name. Required either way: it names the derivation as well as
      the default fetch.
    '';

    rev = optional types.str ''
      Git revision for the default fetch. Defaults to `v''${version}`.
    '';

    hash = optional types.str ''
      Hash of the default fetch. Required unless `src` is supplied.
    '';

    src = optional types.raw ''
      Source tree, overriding the default `fetchFromGitHub` of
      `owner`/`repo`/`rev`/`hash`. Accepts a plain path, a store path, or any
      fetcher output. When set, `owner` and `hash` may be omitted.
    '';

    fetchSubmodules = mkOption {
      type = types.bool;
      default = false;
      description = "Passed through to the default `fetchFromGitHub`.";
    };

    vendorHash = required types.str ''
      Go module vendor hash for the provider build under `provider/`.
    '';

    extraLdflags = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Appended to the `-s -w` ldflags. Conventionally carries the
        `-X .../version.Version=v''${version}` stamp.
      '';
    };

    env = mkOption {
      type = types.attrsOf types.raw;
      default = { };
      description = "Extra environment forwarded into `buildGoModule`.";
    };
  };

  goCmds = {
    cmdGen = required types.str ''
      Name of the schema-generation command under `provider/cmd/`, e.g.
      `pulumi-tfgen-random` or `pulumi-gen-command`.
    '';

    cmdRes = required types.str ''
      Name of the resource plugin command under `provider/cmd/`, e.g.
      `pulumi-resource-random`.
    '';
  };

  componentSource = {
    pname = required types.str "Package name.";

    src = required types.raw ''
      The component provider's source tree: a directory carrying a
      `PulumiPlugin.yaml` at its root.

      Note `src = ./.` inside a flake only sees git-tracked files, so an
      untracked `PulumiPlugin.yaml` or lockfile must be `git add`ed first.
    '';
  };

  componentSchema = {
    languagePlugin = required types.package ''
      The `pulumi-language-<runtime>` host that serves the component's
      `GetSchema` RPC, e.g. `pkgs.pulumiPackages.pulumi-nodejs`.
    '';

    lockFile = optional types.raw ''
      The component's own `package-lock.json`, selecting the npm path. Paired
      with `npmDepsHash`; exactly one of that pair and the
      `yarnLockFile`/`yarnDepsHash` pair is required.
    '';

    npmDepsHash = optional types.str "Hash of the component's npm dependencies.";

    yarnLockFile = optional types.raw ''
      The component's own `yarn.lock`, selecting the yarn classic path instead
      of npm, for components whose `yarn.lock` cannot be converted losslessly.
      Paired with `yarnDepsHash`.
    '';

    yarnDepsHash = optional types.str "Hash of the component's yarn dependencies.";

    sourceRoot = optional types.str "Subdirectory of `src` holding `PulumiPlugin.yaml`.";

    providerPlugins = mkOption {
      type = types.listOf (
        types.either types.package (
          types.submodule {
            options = {
              name = required types.str "Provider plugin name, e.g. `github`.";
              version = required types.str "Provider plugin version.";
              plugin = required types.raw "Extracted `pulumi-resource-<name>` tree.";
            };
          }
        )
      );
      default = [ ];
      description = ''
        Seeds the plugin cache for components importing another provider's SDK,
        which `get-schema` would otherwise try to download with no network.

        A plain package (e.g. `pkgs.pulumiPackages.github`) is enough: its name
        and version are read off the package itself (`meta.mainProgram`,
        `version`). Fall back to the explicit `{ name, version, plugin }` form
        for a plugin that isn't a package built by this repo's builders, or
        whose `meta.mainProgram` isn't set.
      '';
    };
  };
}
