# Usage

Every builder is reachable three ways: the [flake module](#flake-module), the [overlay](#overlay), and `pulumi2nix.lib` with `callPackage`.
The buildable source for every example is under [`examples/`](../examples); what follows is the trimmed shape of each.
See [architecture.md](architecture.md) for how the builders relate, and [sdks.md](sdks.md) for what surrounds them: `src` overrides, narrowed SDK sources, consuming a nodejs SDK, drift checks, and generated SDKs.

## Entry points

### Flake module

`pulumi2nix.flakeModules.default` is a [flake-parts](https://flake.parts) module that turns each builder into an option tree and wires results into `packages` and `checks`, including the `passthru.schema` and `passthru.sdks.<lang>` outputs that are otherwise easy to leave untested.

```nix
{
  inputs.pulumi2nix.url = "github:UnstoppableMango/pulumi2nix";

  outputs =
    inputs@{ flake-parts, pulumi2nix, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];
      imports = [ pulumi2nix.flakeModules.default ];

      perSystem = { pkgs, ... }: {
        pulumi.terraformBridgeProviders.pulumi-random = {
          owner = "pulumi";
          repo = "pulumi-random";
          version = "4.14.0";
          hash = "sha256-...";
          vendorHash = "sha256-...";
          cmdGen = "pulumi-tfgen-random";
          cmdRes = "pulumi-resource-random";
          sdks.nodejs = {
            lockFile = ./package-lock.json;
            npmDepsHash = "sha256-...";
          };
          meta.license = pkgs.lib.licenses.asl20;
        };
      };
    };
}
```

That produces `packages.pulumi-random`, `packages.pulumi-random-schema`, `packages.pulumi-random-sdk-nodejs`, and `packages.pulumi-random-sdk-python` (the bridge builder always builds a python SDK), and mirrors all four into `checks`.
Option trees are `pulumi.schemas`, `.nativeSchemas`, `.terraformBridgeSchemas`, `.componentSchemas`, `.nativeProviders`, `.terraformBridgeProviders`, `.dynamicBridgeProviders`, and `.componentPackages`, one per builder above.

Notes on the shape:

- **SDKs are declared as `sdks.<lang>`**, not the `<lang>Args` the builders take; the module translates.
- **Undeclared attributes pass straight through** to `buildGoModule`/`stdenv.mkDerivation`, which is how `postConfigure` and `__darwinAllowLocalNetworking` work. The cost: a misspelled option is accepted as freeform, usually surfacing as "option ... was accessed but has no value defined".
- **Names must be unique across every tree**, flattened outputs included. A schema-only build named `foo-schema` collides with provider `foo`'s flattened schema; the module refuses. Rename, or set `exposeSchema = false`. `sdks.<lang>.exposePackage` / `exposeCheck` do the same per SDK.
- **`pulumi.packages`** is a read-only map of declared builds, useful for a `linkFarm` default package. **`pulumi2nix`** is a module argument holding the instantiated builder set (where `pulumiLanguageDotnet` comes from). **`overlays.pulumiPackages`** carries the declared builds so `pkgs.<name>` resolves.

Every example under [`examples/`](examples) is written this way.

### Overlay

`pulumi2nix.overlays.default` applies every `lib` builder onto `pkgs`, pre-instantiated against it:

```nix
pkgs = import nixpkgs {
  system = "x86_64-linux";
  overlays = [ pulumi2nix.overlays.default ];
};
# pkgs.mkPulumiPackage, pkgs.mkComponentPackage, ... now resolve
my-provider = pkgs.callPackage ./my-provider { };
```

### `lib` and `callPackage`

```nix
flakeLib = pulumi2nix.lib { inherit pkgs; };
my-provider = pkgs.callPackage ./my-provider { inherit (flakeLib) mkPulumiPackage; };
```

Call `lib` once with `pkgs` to get every builder pre-applied, then apply the one you need to a provider's own arguments.

## Builders

### `mkSchema`

The generic base under `mkPulumiSchema` and `mkTerraformBridgeSchema`.
Takes an explicit `schemaCommand` instead of assuming either wrapper's convention, for a gen tool that fits neither.

```nix
{ lib, mkSchema }:
mkSchema rec {
  owner = "pulumi";
  repo = "pulumi-command";
  version = "0.9.0";
  hash = "sha256-...";
  vendorHash = "sha256-...";
  cmdGen = "pulumi-gen-command";
  schemaCommand = "${cmdGen} schema.json --version ${version}";
  meta.license = lib.licenses.asl20;
}
```

### `mkPulumiSchema`

A native provider's `schema.json` via its own `cmd/pulumi-gen-<name>`, without the plugin binary.
See [`examples/pulumi-command-schema`](../examples/pulumi-command-schema).

```nix
{ lib, mkPulumiSchema }:
mkPulumiSchema rec {
  owner = "pulumi";
  repo = "pulumi-command";
  version = "0.9.0";
  hash = "sha256-...";
  vendorHash = "sha256-...";
  cmdGen = "pulumi-gen-command";
  extraLdflags = [ "-X github.com/pulumi/${repo}/provider/pkg/version.Version=v${version}" ];
  meta.license = lib.licenses.asl20;
}
```

### `mkPulumiPackage`

The full native `pulumi-resource-<name>` binary, layering the upstream repo's committed `sdk/<lang>` trees via `<lang>Args`.
See [`examples/pulumi-command`](../examples/pulumi-command).

```nix
{ lib, mkPulumiPackage }:
mkPulumiPackage rec {
  owner = "pulumi";
  repo = "pulumi-command";
  version = "0.9.0";
  hash = "sha256-...";
  vendorHash = "sha256-...";
  cmdGen = "pulumi-gen-command";
  cmdRes = "pulumi-resource-command";
  extraLdflags = [ "-X github.com/pulumi/${repo}/provider/pkg/version.Version=v${version}" ];
  postConfigure = ''
    pushd ..
    ${cmdGen} provider/cmd/pulumi-resource-command/schema.json --version ${version}
    popd
  '';
  nodejsArgs.lockFile = ./package-lock.json;
  nodejsArgs.npmDepsHash = "sha256-...";
  goArgs.vendorHash = "sha256-...";
  dotnetArgs.nugetDeps = ./deps.json;
  meta.license = lib.licenses.asl20;
}
```

### `mkTerraformBridgeSchema`

`schema.json` derived from an upstream Terraform provider by driving [`pkg/tfgen`](https://github.com/pulumi/pulumi-terraform-bridge/tree/master/pkg/tfgen)'s `schema` language.
See [`examples/pulumi-random-schema`](../examples/pulumi-random-schema).

```nix
{ lib, mkTerraformBridgeSchema }:
mkTerraformBridgeSchema rec {
  owner = "pulumi";
  repo = "pulumi-random";
  version = "4.14.0";
  hash = "sha256-...";
  vendorHash = "sha256-...";
  cmdGen = "pulumi-tfgen-random";
  extraLdflags = [ "-X github.com/pulumi/${repo}/provider/v4/pkg/version.Version=v${version}" ];
  meta.license = lib.licenses.asl20;
}
```

### `mkTerraformBridgeProvider`

The full bridged provider binary plus committed SDKs, same `<lang>Args` shape as `mkPulumiPackage`.
See [`examples/pulumi-random`](../examples/pulumi-random).

```nix
{ lib, mkTerraformBridgeProvider }:
mkTerraformBridgeProvider rec {
  owner = "pulumi";
  repo = "pulumi-random";
  version = "4.14.0";
  hash = "sha256-...";
  vendorHash = "sha256-...";
  cmdGen = "pulumi-tfgen-random";
  cmdRes = "pulumi-resource-random";
  extraLdflags = [ "-X github.com/pulumi/${repo}/provider/v4/pkg/version.Version=v${version}" ];
  nodejsArgs.lockFile = ./package-lock.json;
  nodejsArgs.npmDepsHash = "sha256-...";
  meta.license = lib.licenses.asl20;
}
```

This builder and `mkPulumiPackage` (which delegates to it) always build a python SDK, from `sdk/python` unless `pythonArgs.generate` swaps that for codegen.
Its distribution name defaults to `pulumi-` plus `cmdRes` minus the `pulumi-resource-` prefix, so `pulumi-resource-random` gives `pulumi-random`, matching what tfgen writes into the SDK regardless of the repo name; `pythonImportsCheck` replaces `-` with `_`.
Pass `pythonArgs.pname` / `pythonArgs.pythonImportsCheck` for an SDK that does not follow the convention.

It also takes [`sdkDrift`](sdks.md#sdk-drift-checks) and a per-language [`generate`](sdks.md#generated-sdks-for-bridged-providers) flag.

### `mkDynamicBridgeProvider`

The generic binary behind Pulumi's [`terraform-provider`](https://www.pulumi.com/registry/packages/terraform-provider/) package, which bridges any Terraform provider at runtime via [`pulumi package add terraform-provider ...`](https://www.pulumi.com/docs/iac/cli/commands/pulumi_package_add/) instead of being generated ahead of time for one.
`owner`/`repo` default to `pulumi`/`pulumi-terraform-bridge`, where the [`dynamic`](https://github.com/pulumi/pulumi-terraform-bridge/tree/master/dynamic) package actually lives.
See [`examples/pulumi-terraform-provider`](../examples/pulumi-terraform-provider).

```nix
{ lib, mkDynamicBridgeProvider }:
mkDynamicBridgeProvider {
  version = "1.1.3";                                          # names the derivation
  rev = "484f8987228cbec779e11f593bc48c79c49d4f08";           # bridge commit the release was built from
  versionString = "v1.1.3";                                   # what the binary reports
  hash = "sha256-...";
  vendorHash = "sha256-...";
  meta.license = lib.licenses.asl20;
}
```

`versionString` is compiled into `dynamic/version.version`, which `pulumi plugin ls` and plugin-version resolution read.
It defaults to `rev`, which is right when tag and revision are the same string; for this provider they usually aren't, since a `pulumi-terraform-provider` release names a bridge *commit*.
Drop `rev`/`versionString` to build a bridge tag straight through.
Without `versionString` the build still succeeds and reports a 40-character SHA; `extraLdflags` can't fix it after the fact, since it appends and cannot displace the `-X` already in the list.

### `mkComponentSchema`

`schema.json` extracted from a source-based, multi-language [component](https://www.pulumi.com/docs/iac/concepts/resources/components/) provider (a directory carrying `PulumiPlugin.yaml`) by shelling out to [`pulumi package get-schema`](https://www.pulumi.com/docs/iac/cli/commands/pulumi_package_get-schema/), which runs the component's own source.
See [`examples/test-component-schema`](../examples/test-component-schema).

```nix
{ lib, mkComponentSchema, pulumiPackages }:
mkComponentSchema {
  pname = "test-component-schema";
  version = "0.0.1";
  src = ./.;
  languagePlugin = pulumiPackages.pulumi-nodejs;
  lockFile = ./package-lock.json;
  npmDepsHash = "sha256-...";
  meta.license = lib.licenses.asl20;
}
```

**npm or yarn classic.**
`get-schema` runs the nodejs install itself and picks its package manager from the lockfile in the tree, so the pair passed selects the dependency path: `lockFile` + `npmDepsHash` (`fetchNpmDeps`), or `yarnLockFile` + `yarnDepsHash` (`fetchYarnDeps` + `yarnConfigHook`, see [`examples/test-component-yarn`](../examples/test-component-yarn)).
Exactly one complete pair is required; both or neither is an error.
Discover the hash by setting it to `lib.fakeHash` and reading the real value out of the first build failure.

**Components importing another provider's SDK** need that provider's plugin seeded into the cache, since `get-schema` otherwise tries to download it with no network in the sandbox. A plain package is enough; its name and version are read off `meta.mainProgram` (`pulumi-resource-<name>`) and `version`:

```nix
providerPlugins = [
  pkgs.pulumiPackages.github
];
```

Fall back to the explicit form for a plugin that isn't a package built by this repo's builders, or whose `meta.mainProgram` isn't set:

```nix
providerPlugins = [
  {
    name = "github";
    version = "6.15.0";
    plugin = pkgs.fetchurl { /* pulumi-resource-github tarball, extracted */ };
  }
];
```

**Component class shape.**
`get-schema`'s analyzer only recognizes classes extending `ComponentResource` directly: it walks one heritage-clause level.
An intermediate base class (`Fork extends Repo extends ComponentResource`) is invisible to it and fails with a generic "Failed to find the following components".
It also can't resolve utility or indexed-access types (`Omit<X, "y">`, `X["y"]`) in an args interface, throwing `Unsupported type for component ... property ...`.
Keep components extending `ComponentResource` directly and args interfaces plain.

**Untracked files.**
`src = ./.` in a flake only sees git-tracked files, so an untracked `PulumiPlugin.yaml` or lockfile needs `git add`ing first, or `mkComponentPackage`'s "expected PulumiPlugin.yaml" check fails misleadingly.

### `mkComponentPackage`

Packages a component provider and layers generated SDKs on its extracted schema, since this shape has no compiled resource binary.
See [`examples/test-component`](../examples/test-component), or [`examples/test-component-yarn`](../examples/test-component-yarn) for a yarn classic tree.

```nix
{ lib, mkComponentPackage, pulumiPackages, pulumiLanguageDotnet }:
mkComponentPackage {
  pname = "test-component";
  version = "0.0.1";
  src = ./.;
  schemaArgs = {
    languagePlugin = pulumiPackages.pulumi-nodejs;
    lockFile = ./package-lock.json;
    npmDepsHash = "sha256-...";
  };
  nodejsArgs = {
    languagePlugin = pulumiPackages.pulumi-nodejs;
    lockFile = ./generated-sdk/nodejs/package-lock.json;
    npmDepsHash = "sha256-...";
  };
  goArgs = {
    languagePlugin = pulumiPackages.pulumi-go;
    importBasePath = "github.com/you/your-repo/sdk/go/yourcomponent";
    goMod = ./generated-sdk/go/go.mod;
    goSum = ./generated-sdk/go/go.sum;
    vendorHash = "sha256-...";
  };
  dotnetArgs = {
    languagePlugin = pulumiLanguageDotnet;
    nugetDeps = ./generated-sdk/dotnet/deps.json;
  };
  meta.license = lib.licenses.asl20;
}
```

`schemaArgs`' package manager is independent of the generated SDKs', whose source is codegen output with its own dependency set.

**Go module files.**
`gen-sdk --language go` emits only `.go` sources: no `go.mod`, no `go.sum`.
A module path is external convention, and filling in a `require` block needs a real `go mod tidy` against the network, which a sandboxed derivation can't do, so `goArgs` takes both files from the caller plus an `importBasePath`.
Without it codegen falls back to an `example.com/...` path and writes self-imports that don't match the directories it created.

```sh
nix build .#your-package-schema --out-link /tmp/schema

tmp=$(mktemp -d); cd "$tmp"
jq '.language.go.importBasePath = "github.com/you/your-repo/sdk/go/yourcomponent"' \
  /tmp/schema/schema.json > schema.json

nix shell nixpkgs#pulumi nixpkgs#pulumiPackages.pulumi-go -c \
  pulumi package gen-sdk schema.json --language go --out .

nix shell nixpkgs#go -c go mod init github.com/you/your-repo/sdk
nix shell nixpkgs#go -c go mod tidy
```

`importBasePath` is the module path plus `/go/<dir>`; its last segment becomes the package directory under `go/`.
Keep the resulting `go` directive at or below the `go` version in your pinned nixpkgs so the sandbox never downloads a toolchain, then set `vendorHash = lib.fakeHash` and read the real hash out of the first build failure.

### `mkGeneratedSdk`

The lower-level builder `<lang>Args` blocks resolve to under `mkComponentPackage`: runs `pulumi package gen-sdk` against a schema derivation (anything exposing `$out/schema.json`) using that language's `pulumi-language-<lang>` plugin.
`schemaOverrides` is merged into the schema before codegen, which is how per-language settings get into a schema extracted from source.

```nix
{ mkGeneratedSdk, mkComponentSchema, pulumiPackages }:
mkGeneratedSdk {
  pname = "test-component";
  version = "0.0.1";
  schema = mkComponentSchema { /* ... */ };
  lang = "nodejs";
  languagePlugin = pulumiPackages.pulumi-nodejs;
  # schemaOverrides.language.go.importBasePath = "github.com/you/your-repo/sdk/go/yourcomponent";
}
```

### `mkGeneratedGoSdk`

Completes `mkGeneratedSdk`'s go output into a buildable module by copying a caller-supplied `go.mod`/`go.sum` into the module root, producing the `sdk/{go.mod,go.sum,go/...}` layout `lib/sdks/go.nix` expects.
`goArgs` under `mkComponentPackage` wires this up automatically.

```nix
{ mkGeneratedGoSdk, mkGeneratedSdk, pulumiPackages }:
mkGeneratedGoSdk {
  pname = "test-component";
  version = "0.0.1";
  src = mkGeneratedSdk {
    lang = "go";
    languagePlugin = pulumiPackages.pulumi-go;
    schemaOverrides.language.go.importBasePath = "github.com/you/your-repo/sdk/go/yourcomponent";
    # ...
  };
  goMod = ./generated-sdk/go/go.mod;
  goSum = ./generated-sdk/go/go.sum;
}
```

### `pulumiLanguageDotnet`

A pinned build of the `pulumi-language-dotnet` host, filling the gap left by nixpkgs' `pulumiPackages` (Go, Node.js and Python only).
It is patched to read a nix-fetched `pulumi_logo_64x64.png` instead of downloading one, which is what lets `gen-sdk --language dotnet` run in a sandbox at all.
The tradeoff: a schema's `logoUrl` no longer affects the generated `logo.png`, so every .NET SDK gets the generic Pulumi icon.
Feed it as the `languagePlugin` for any `dotnetArgs` block.
