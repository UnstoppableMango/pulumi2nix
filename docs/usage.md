# Usage

Every builder is reachable three ways: the [flake module](#flake-module), the [overlay](#overlay), and `pulumi2nix.lib` with `callPackage`.
The buildable source for every example is under [`examples/`](../examples); what follows is the trimmed shape of each.
See [architecture.md](architecture.md) for how the builders relate, and [sdks.md](sdks.md) for what surrounds them: `src` overrides, narrowed SDK sources, consuming a nodejs SDK, drift checks, and generated SDKs.

The library is two layers.
[Artifact builders](#artifact-builders) build one Pulumi artifact each and compose nothing.
[Package recipes](#package-recipes) compose those into a provider you can hand to Pulumi, and are what the flake module and most callers use.

## Entry points

### Flake module

`pulumi2nix.flakeModules.default` is a [flake-parts](https://flake.parts) module that turns each recipe into an option tree and wires results into `packages` and `checks`, including the `passthru.schema` and `passthru.sdks.<lang>` outputs that are otherwise easy to leave untested.

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
          sdks.python = { };
          meta.license = pkgs.lib.licenses.asl20;
        };
      };
    };
}
```

That produces `packages.pulumi-random`, `packages.pulumi-random-schema`, `packages.pulumi-random-sdk-nodejs` and `packages.pulumi-random-sdk-python`, and mirrors all four into `checks`.
Option trees are `pulumi.schemas`, `.nativeSchemas`, `.terraformBridgeSchemas`, `.componentSchemas`, `.nativeProviders`, `.terraformBridgeProviders`, `.dynamicBridgeProviders`, and `.componentPackages`.

Notes on the shape:

- **SDKs are declared as `sdks.<lang>`**, not the `<lang>Args` the builders take; the module translates. Every language is opt-in, python included: `sdks.python = { }` is enough to ask for one.
- **Undeclared attributes pass straight through** to `buildGoModule`/`stdenv.mkDerivation`, which is how `__darwinAllowLocalNetworking` works. The cost: a misspelled option is accepted as freeform, usually surfacing as "option ... was accessed but has no value defined".
- **Names must be unique across every tree**, flattened outputs included. A schema-only build named `foo-schema` collides with provider `foo`'s flattened schema; the module refuses. Rename, or set `exposeSchema = false`. `sdks.<lang>.exposePackage` / `exposeCheck` do the same per SDK.
- **`pulumi.packages`** is a read-only map of declared builds, useful for a `linkFarm` default package. **`pulumi2nix`** is a module argument holding the instantiated builder set (where `pulumiLanguageDotnet` comes from). **`overlays.pulumiPackages`** carries the declared builds so `pkgs.<name>` resolves.

Every example under [`examples/`](../examples) is written this way.

### Overlay

`pulumi2nix.overlays.default` applies every `lib` builder onto `pkgs`, pre-instantiated against it:

```nix
pkgs = import nixpkgs {
  system = "x86_64-linux";
  overlays = [ pulumi2nix.overlays.default ];
};
# pkgs.mkPulumiPackage, pkgs.mkSdkSource, ... now resolve
my-provider = pkgs.callPackage ./my-provider { };
```

### `lib` and `callPackage`

```nix
flakeLib = pulumi2nix.lib { inherit pkgs; };
my-provider = pkgs.callPackage ./my-provider { inherit (flakeLib) mkPulumiPackage; };
```

Call `lib` once with `pkgs` to get every builder pre-applied, then apply the one you need to a provider's own arguments.

## Package recipes

### `mkPulumiPackage`

A native provider: gen tool, schema, `pulumi-resource-<name>` binary, and SDKs.
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
  nodejsArgs.lockFile = ./package-lock.json;
  nodejsArgs.npmDepsHash = "sha256-...";
  goArgs.vendorHash = "sha256-...";
  dotnetArgs.nugetDeps = ./deps.json;
  pythonArgs = { };
  meta.license = lib.licenses.asl20;
}
```

The schema is built from `cmd/pulumi-gen-<name>`, which takes an explicit output path plus `--version`, and is exposed as `passthru.schema`.
It is *not* planted into the plugin build: a [`pulumi-go-provider`](https://github.com/pulumi/pulumi-go-provider) provider serves its schema from Go structs at runtime and embeds nothing.
A native provider that does embed one sets `embedSchema = true`, and `schemaPath` if it reads the file somewhere other than `provider/cmd/<cmdRes>/schema.json`.

### `mkTerraformBridgeProvider`

The same for a provider bridged from Terraform ahead of time, with the schema coming from [`pkg/tfgen`](https://github.com/pulumi/pulumi-terraform-bridge/tree/master/pkg/tfgen)'s `schema` language.
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
  pythonArgs = { };
  meta.license = lib.licenses.asl20;
}
```

Here `embedSchema` defaults to true: the built `schema.json` is planted at `provider/cmd/<cmdRes>/schema.json`, where the repo's own `generate.go` reads it and writes the version-stamped `schema-embed.json` that `main.go` embeds.
The schema is therefore built once and used twice, rather than regenerated inside the plugin build.

It also takes [`sdkDrift`](sdks.md#sdk-drift-checks) and a per-language [`generate`](sdks.md#generated-sdks-for-bridged-providers) flag.

**Python.** Its distribution name follows the plugin rather than the repo: `cmdRes = "pulumi-resource-random"` gives `pulumi-random`, which is what tfgen writes into the SDK regardless of the repo name.
Both recipes default `pythonArgs.distName` that way, and `pythonImportsCheck` replaces `-` with `_`.
Pass `pythonArgs.distName` for an SDK that does not follow the convention.

### `mkProviderPackage`

What both presets sit on, for a provider fitting neither convention.
It takes the same arguments plus an explicit `schemaCommand`, run at the repo root with the gen tool on `PATH`, and must leave `schema.json` behind:

```nix
{ mkProviderPackage }:
mkProviderPackage rec {
  # ... as above ...
  schemaCommand = "${cmdGen} --emit-schema ./schema.json";
  embedSchema = true;
}
```

A `postConfigure` of your own is forwarded to the plugin build, and so is `nativeBuildInputs`.
The gen tool is not among them: a hook that runs it in place has to ask for it, with `nativeBuildInputs = [ (mkGenTool { /* ... */ }) ]`.
Prefer `embedSchema`, which plants the already-built `schema.json` instead of generating a second copy.

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
  pythonArgs.languagePlugin = pulumiPackages.pulumi-python;
  meta.license = lib.licenses.asl20;
}
```

Every language is generated from the schema here, since a component provider commits no SDK tree, so `generate` is implied and each language needs its own `languagePlugin`.
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

### `mkDynamicBridgeProvider`

The generic binary behind Pulumi's [`terraform-provider`](https://www.pulumi.com/registry/packages/terraform-provider/) package, which bridges any Terraform provider at runtime via [`pulumi package add terraform-provider ...`](https://www.pulumi.com/docs/iac/cli/commands/pulumi_package_add/) instead of being generated ahead of time for one.
It has no schema and no SDKs, so the recipe is exactly [`mkDynamicPlugin`](#mkdynamicplugin) under its older name.

## Artifact builders

### `mkGenTool`

The provider repo's `cmd/pulumi-tfgen-<name>` or `cmd/pulumi-gen-<name>` binary, built out of `provider/`.

```nix
{ mkGenTool }:
mkGenTool rec {
  owner = "pulumi";
  repo = "pulumi-random";
  version = "4.14.0";
  hash = "sha256-...";
  vendorHash = "sha256-...";
  cmdGen = "pulumi-tfgen-random";
  extraLdflags = [ "-X github.com/pulumi/${repo}/provider/v4/pkg/version.Version=v${version}" ];
}
```

`meta.mainProgram` is set to `cmdGen`, so `lib.getExe` finds the binary and anything downstream can recover its name from the derivation alone.
Both `mkSchema` and `mkSdkSource`'s gen-tool route take one as an input, which is why a provider that needs the tool twice builds it once.

### `mkSchema`

`schema.json`, by running that gen tool.
`schemaCommand` is the tool's own invocation, run at the repo root with the tool on `PATH`, and has to leave `schema.json` in the working directory.

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

Pass `genTool` to reuse a build; otherwise it constructs one from the same arguments.
The tool used is exposed as `passthru.genTool`.

Two presets fill in `schemaCommand` for the conventions that exist:
**`mkPulumiSchema`** for a native gen tool (`<cmdGen> schema.json --version <version>`, see [`examples/pulumi-command-schema`](../examples/pulumi-command-schema)) and **`mkTerraformBridgeSchema`** for tfgen (`<cmdGen> schema --out .`, see [`examples/pulumi-random-schema`](../examples/pulumi-random-schema)).
Both take exactly the arguments above minus `schemaCommand`.

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
`src = ./.` in a flake only sees git-tracked files, so an untracked `PulumiPlugin.yaml` or lockfile needs `git add`ing first, or `mkComponentPlugin`'s "expected PulumiPlugin.yaml" check fails misleadingly.

### `mkProviderPlugin`

The `pulumi-resource-<name>` binary out of the repo's `provider/` module, and nothing else.

```nix
{ mkProviderPlugin, mkTerraformBridgeSchema }:
mkProviderPlugin rec {
  owner = "pulumi";
  repo = "pulumi-random";
  version = "4.14.0";
  hash = "sha256-...";
  vendorHash = "sha256-...";
  cmdRes = "pulumi-resource-random";

  schema = mkTerraformBridgeSchema { /* ... */ };
  # schemaPath = "provider/cmd/${cmdRes}/schema.json";  # the default
  # goGenerate = true;                                  # defaults to schema != null
}
```

`schema` is planted at `schemaPath` before the build and `go generate cmd/<cmdRes>/main.go` is run over it, which is how a bridged provider ends up embedding it.
Leave `schema` unset for a provider that carries no schema in its binary; then no gen tool is involved in the plugin build at all.
Anything else is forwarded to `buildGoModule`, and a `postConfigure` of your own is appended after the schema and `go generate` steps rather than replacing them.
A hook needing tools of its own takes them through `nativeBuildInputs` like any other `buildGoModule` call, the gen tool included.

### `mkComponentPlugin`

A component provider's plugin: its source tree plus `PulumiPlugin.yaml`, validated and installed.
There is no binary to compile.

```nix
{ mkComponentPlugin, mkComponentSchema }:
mkComponentPlugin {
  pname = "test-component";
  version = "0.0.1";
  src = ./.;
  schema = mkComponentSchema { /* ... */ };  # optional, becomes passthru.schema
}
```

### `mkDynamicPlugin`

The generic `pulumi-resource-terraform-provider` binary.
`owner`/`repo` default to `pulumi`/`pulumi-terraform-bridge`, where the [`dynamic`](https://github.com/pulumi/pulumi-terraform-bridge/tree/master/dynamic) package actually lives.
See [`examples/pulumi-terraform-provider`](../examples/pulumi-terraform-provider).

```nix
{ lib, mkDynamicPlugin }:
mkDynamicPlugin {
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

### `mkSdkSource`

One language's SDK source tree: the artifact between `schema.json` and a packaged SDK.
Whichever producer runs, the result holds the SDK at `sdk/<lang>`, which is the layout every builder in `lib/sdks` expects.

Pick a producer by which argument you pass:

```nix
# 1. the upstream repo's committed tree, narrowed to what this language builds from
mkSdkSource {
  pname = "pulumi-random"; version = "4.14.0"; lang = "nodejs";
  src = ./checkout;
  # narrowSrc = false; srcPaths = [ ... ];   # see sdks.md
}

# 2. codegen from a schema
mkSdkSource {
  pname = "test-component"; version = "0.0.1"; lang = "go";
  schema = mkComponentSchema { /* ... */ };
  languagePlugin = pulumiPackages.pulumi-go;
  schemaOverrides.language.go.importBasePath = "github.com/you/your-repo/sdk/go/yourcomponent";
  goMod = ./generated-sdk/go/go.mod;
  goSum = ./generated-sdk/go/go.sum;
}

# 3. the provider's own gen tool, which replays tfgen's language overlays
mkSdkSource {
  pname = "pulumi-random"; version = "4.14.0"; lang = "nodejs";
  src = ./checkout;
  genTool = mkGenTool { /* ... */ };
}
```

`schemaOverrides` is merged into the schema before codegen, which is how per-language settings get into a schema extracted from source.
`goMod`/`goSum` complete a generated go tree in the same derivation, since `gen-sdk` never emits them.

### `mkSdk`

One packaged SDK, dispatching by language name to the registry in `lib/sdks`: `nodejs` (npm), `yarnNodejs` (yarn classic), `go`, `dotnet`, `python`.

```nix
{ mkSdk, mkSdkSource }:
mkSdk "my-flake" "nodejs" {
  pname = "pulumi-random-sdk-nodejs";
  version = "4.14.0";
  src = mkSdkSource { /* ... */ };
  lockFile = ./package-lock.json;
  npmDepsHash = "sha256-...";
}
```

The first argument names the caller, so an unregistered language produces a message pointing at whoever asked for it.
What each language needs beyond `src` is in [sdks.md](sdks.md).

## Utilities

### `withSdks`

Attaches `<lang>Args`-driven SDK builds to any base derivation's `passthru.sdks`, resolving each language's source through `mkSdkSource`.
`generate = true` on a language picks the schema producer; otherwise it reads the committed tree.
It overrides onto whatever the base already carries, so it can be layered more than once.

```nix
{ withSdks }:
withSdks {
  base = someProviderDerivation;
  pname = "pulumi-random";
  version = "4.14.0";
  src = ./checkout;
  schema = someSchemaDerivation;    # only needed by generated languages

  nodejsArgs = { lockFile = ./package-lock.json; npmDepsHash = "sha256-..."; };
  pythonArgs.generate = true;
  pythonArgs.languagePlugin = pulumiPackages.pulumi-python;
}
```

### `mkSdkDriftCheck`

Fails when a provider's committed `sdk/<lang>` doesn't match what the provider generates.
It generates nothing itself: both sides are `mkSdkSource` trees, so the choice of generator stays with the caller.
See [sdks.md](sdks.md#sdk-drift-checks) for the `sdkDrift` option the provider recipes drive it with.

```nix
{ mkSdkDriftCheck, mkSdkSource }:
mkSdkDriftCheck {
  pname = "pulumi-random";
  lang = "nodejs";
  committed = mkSdkSource { lang = "nodejs"; src = ./checkout; /* ... */ };
  against = mkSdkSource { lang = "nodejs"; src = ./checkout; genTool = ...; /* ... */ };
  # exclude / extraExclude / committedPath / againstPath
}
```

### `pulumiLanguageDotnet`

A pinned build of the `pulumi-language-dotnet` host, filling the gap left by nixpkgs' `pulumiPackages` (Go, Node.js and Python only).
It is patched to read a nix-fetched `pulumi_logo_64x64.png` instead of downloading one, which is what lets `gen-sdk --language dotnet` run in a sandbox at all.
The tradeoff: a schema's `logoUrl` no longer affects the generated `logo.png`, so every .NET SDK gets the generic Pulumi icon.
Feed it as the `languagePlugin` for any `dotnetArgs` block.

## Deprecated

Kept so existing callers keep working; each forwards to its replacement.

| Old | Use instead |
| --- | --- |
| `mkGeneratedSdk` | [`mkSdkSource`](#mksdksource) with a `schema` |
| `mkGeneratedGoSdk` | `mkSdkSource`'s `goMod`/`goSum`, which complete a generated go tree in the same derivation |
| `withGeneratedSdks` | [`withSdks`](#withsdks), which covers both SDK source routes |
