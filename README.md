# pulumi2nix

[![CI](https://github.com/UnstoppableMango/pulumi2nix/actions/workflows/ci.yml/badge.svg)](https://github.com/UnstoppableMango/pulumi2nix/actions/workflows/ci.yml)
[![Built with Nix](https://img.shields.io/badge/built%20with-nix-5277C3?logo=nixos&logoColor=white)](https://builtwithnix.org)
[![License: MIT](https://img.shields.io/github/license/UnstoppableMango/pulumi2nix)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/UnstoppableMango/pulumi2nix)](https://github.com/UnstoppableMango/pulumi2nix/commits/main)

Composable Nix builders for Pulumi providers, packages, and language SDKs.

## What this provides

pulumi2nix is a library of composable Nix builders that model the distinct stages of producing a Pulumi provider, so that packaging one is a matter of composing existing functions rather than reverse-engineering a bespoke build for each provider.

- **Native provider plugin binaries.**
`mkPulumiSchema` and `mkSchema` invoke a provider's own `cmd/pulumi-gen-<name>` tool to produce `schema.json`, and `mkPulumiPackage` builds on that to produce the full `pulumi-resource-<name>` plugin binary.

- **Bridged providers, generated from Terraform.**
`mkTerraformBridgeSchema` and `mkTerraformBridgeProvider` drive `tfgen`'s `schema` language to derive a schema from an upstream Terraform provider, then build the resulting `pulumi-tfgen-<name>` bridged plugin binary from it.

- **Dynamically bridged providers.**
`mkDynamicBridgeProvider` builds the generic `pulumi-resource-terraform-provider` binary from `pulumi/pulumi-terraform-bridge`'s `dynamic` package, which bridges *any* Terraform provider at runtime via parameterization (`pulumi package add terraform-provider ...`) instead of being generated ahead-of-time for one specific upstream provider.

- **Providers generated from non-Terraform schema sources.**
The same schema-then-package pattern extends to providers whose schema originates from OpenAPI or CloudFormation resource definitions, such as the `*-native` provider family, rather than from Terraform or a native Go generator.

- **Component provider packages.**
`mkComponentSchema` extracts a schema from a source-based, multi-language component provider (a directory carrying a `PulumiPlugin.yaml`) by shelling out to `pulumi package get-schema`, which launches the runtime's own `pulumi-language-<runtime>` host to serve the `GetSchema` RPC directly from source. `mkComponentPackage` packages that source tree and layers generated SDKs on top, since there is no compiled resource binary to build for this provider shape.

- **Schema generation, independent of the plugin binary.**
Every builder above separates schema extraction from binary packaging, so `schema.json` can be produced and consumed (for SDK generation, validation, or publishing) without paying for a full provider build.

- **Language SDK generation.**
`mkGeneratedSdk` runs `pulumi package gen-sdk` against a `schema.json` output using the target language's `pulumi-language-<lang>` plugin, covering Node.js, Python, and Go from nixpkgs' `pulumiPackages`, and .NET via this repo's own pinned `pulumi-language-dotnet` build (upstream `pulumi/pulumi-dotnet` has no packaged language host in nixpkgs). Java is not supported.
Go additionally goes through `mkGeneratedGoSdk`, which attaches the `go.mod`/`go.sum` pair that `gen-sdk` never emits.

## Usage

There are three entry points, in increasing order of how much plumbing they do for you: the [flake module](#flake-module), the [overlay](#overlay), and `pulumi2nix.lib` with `callPackage`.

### Flake module

`pulumi2nix.flakeModules.default` is a [flake-parts](https://flake.parts) module that turns each builder into an option tree, instantiates the builders per system, and wires the results into `packages` and `checks` - including the `passthru.schema` and `passthru.sdks.<lang>` outputs that are otherwise easy to leave untested.

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

That single declaration produces:

| Output | From |
| --- | --- |
| `packages.pulumi-random` | the declaration itself |
| `packages.pulumi-random-schema` | its `passthru.schema` |
| `packages.pulumi-random-sdk-nodejs` | its `passthru.sdks.nodejs` |
| `packages.pulumi-random-sdk-python` | ditto - the bridge builder always builds a python SDK |

and mirrors all four into `checks`.

One option tree per builder:

| Option tree | Builder |
| --- | --- |
| `pulumi.schemas.<name>` | [`mkSchema`](#mkschema) |
| `pulumi.nativeSchemas.<name>` | [`mkPulumiSchema`](#mkpulumischema) |
| `pulumi.terraformBridgeSchemas.<name>` | [`mkTerraformBridgeSchema`](#mkterraformbridgeschema) |
| `pulumi.componentSchemas.<name>` | [`mkComponentSchema`](#mkcomponentschema) |
| `pulumi.nativeProviders.<name>` | [`mkPulumiPackage`](#mkpulumipackage) |
| `pulumi.terraformBridgeProviders.<name>` | [`mkTerraformBridgeProvider`](#mkterraformbridgeprovider) |
| `pulumi.dynamicBridgeProviders.<name>` | [`mkDynamicBridgeProvider`](#mkdynamicbridgeprovider) |
| `pulumi.componentPackages.<name>` | [`mkComponentPackage`](#mkcomponentpackage) |

Notes on the shape:

- **SDKs are declared as `sdks.<lang>`**, not the `<lang>Args` the builders take. `lib/lang-arg-names.nix` selects languages by the string suffix `Args` on any key, which would be ambiguous next to the freeform escape hatch below; the module translates `sdks.go` to `goArgs` when it calls the builder.
- **Undeclared attributes pass straight through** to `buildGoModule`/`stdenv.mkDerivation`, the same way the builders themselves forward them. That is how `postConfigure` and `__darwinAllowLocalNetworking` work. The cost is that a misspelled option name is accepted as a freeform attribute rather than rejected, so a typo usually surfaces as "option ... was accessed but has no value defined" for the option you meant to set.
- **Names must be unique across every tree, flattened outputs included.** A schema-only build named `foo-schema` collides with provider `foo`'s flattened `passthru.schema`; the module refuses rather than silently dropping one. Rename it, or set `exposeSchema = false` on the provider. `sdks.<lang>.exposePackage` and `sdks.<lang>.exposeCheck` do the same for an individual SDK - set `exposeCheck = false` to keep an SDK whose build is known-broken or prohibitively slow out of `nix flake check`.
- **`pulumi.packages`** is a read-only map of the declared builds (no flattened schemas or SDKs), useful for a `linkFarm` default package.
- **`pulumi2nix`** is available as a module argument holding the instantiated builder set, which is where `pulumiLanguageDotnet` comes from.
- **`overlays.pulumiPackages`** carries the declared builds for the current system, so `pkgs.<name>` resolves after applying it. (It is distinct from `overlays.default`, which applies the *builders* onto `pkgs`.)
- **`sdkDrift`** on a bridged provider adds [SDK drift checks](#sdk-drift-checks), which are the only outputs that land in `checks` without a matching entry in `packages`.

Every example under [`examples/`](examples) is written this way.

### `lib` and `callPackage`

Add this repo as a flake input, then obtain each builder via `callPackage` against `pulumi2nix.lib`.

```nix
{
  inputs.pulumi2nix.url = "github:UnstoppableMango/pulumi2nix";

  outputs = { self, nixpkgs, pulumi2nix }: {
    packages.x86_64-linux =
      let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        flakeLib = pulumi2nix.lib { inherit pkgs; };
        mkPulumiPackage = flakeLib.mkPulumiPackage;
      in
      {
        my-provider = pkgs.callPackage ./my-provider { inherit mkPulumiPackage; };
      };
  };
}
```

Each builder below is instantiated the same way: call `lib` once with `pkgs` to get back every builder pre-applied, then apply the one you need to a provider's own arguments.
The full, buildable source for every example is under [`examples/`](examples); what follows is the trimmed shape of each one.

### Overriding the source

Every builder that fetches an upstream provider (`mkSchema`, `mkPulumiSchema`, `mkTerraformBridgeSchema`, `mkPulumiPackage`, `mkTerraformBridgeProvider`, `mkDynamicBridgeProvider`, `withSdks`) accepts an optional `src`.
It defaults to a `fetchFromGitHub` of `owner`/`repo`/`rev`/`hash`, so the examples below never set it.
Pass `src` to build from a local checkout, a patched tree, or a different fetcher:

```nix
mkTerraformBridgeProvider {
  repo = "pulumi-random";
  version = "4.14.0";
  src = ./my-checkout; # or fetchgit, fetchzip, a flake input, ...
  vendorHash = "sha256-...";
  cmdGen = "pulumi-tfgen-random";
  cmdRes = "pulumi-resource-random";
}
```

`owner` and `hash` are only forced by the default fetch, so a caller supplying `src` can omit them.
`repo` is required either way, and `rev` defaults to `v${version}`: both name the derivation.
`mkDynamicBridgeProvider` also compiles a version into its binary, but through its own [`versionString`](#mkdynamicbridgeprovider), which defaults to `rev` and can be set independently when the release tag and the source revision differ.
Layered SDKs take a lang-qualified derivation name, `<repo>-sdk-<lang>`, matching the flattened `packages.<name>-sdk-<lang>` output, so a provider and its SDKs stay distinguishable in store paths and build logs.
Set `pname` on the individual `sdks.<lang>` block (or `<lang>Args`) to override it.

`sourceRoot` is resolved from the `src`'s name, so any fetcher output, a `lib.cleanSourceWith`, a plain path, and a store path all work.
A path value is handled on its own terms: taking one as a build input copies it into the store under its own basename, so the name `sourceRoot` is built from keeps that basename whole rather than treating a leading hash as the store's.
That matters for a path that already lives in the store, whose basename is itself `<hash>-<name>`.

`lib.fileset.toSource` is the preferred way to hand in a local checkout, because it names its result explicitly instead of leaving the name to be recovered from a store path:

```nix
src = lib.fileset.toSource {
  root = ./.;
  fileset = lib.fileset.unions [ ./provider ./sdk ];
};
```

Note the caveat below about `src = ./.` inside a flake only seeing git-tracked files.

### Narrowed SDK sources

The provider, the schema and every checked-in SDK share one `src`, but each SDK only ever builds from its own subtree.
Each one is therefore handed a `lib.fileset`-narrowed copy of that tree rather than the whole thing, so editing a file no SDK reads (a README, a CI workflow, the Makefile) no longer changes those SDKs' input hashes and no longer rebuilds them.

| SDK | Paths kept |
| --- | --- |
| `sdks.go` | `sdk/go`, `sdk/go.mod`, `sdk/go.sum` |
| `sdks.nodejs`, `sdks.yarnNodejs` | `sdk/nodejs`, `README.md`, `LICENSE` |
| `sdks.dotnet` | `sdk/dotnet` |
| `sdks.python` | `sdk/python` |

`README.md` and `LICENSE` are in the nodejs list because the SDK build copies them next to its compiled output.
Paths that a given repo does not have are skipped rather than failing, and if the SDK's own directory is missing the whole tree is kept, on the assumption that the layout is not the one above.

The provider and schema builds keep the whole tree: `postConfigure` runs the gen tool from the repo root, and tfgen reads the upstream provider's docs.

Narrowing needs a tree that can be read while the expression evaluates: a path, or any value that stringifies to a store path already realized on disk.
A `src` that is still an unbuilt derivation - the default `fetchFromGitHub` fetch - is passed through untouched, which costs nothing: that output only moves when `rev` does.

To narrow a provider's own repo, give the derivation an explicit `src` naming the subset the builds read:

```nix
pulumi.terraformBridgeProviders.pulumi-resource-git = {
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./provider ./sdk ];
  };
  # ...
};
```

`lib.fileset.toSource` is the recommended shape because it names its own result, which is what `sourceRoot` is resolved from, and because it puts the tree the provider and schema builds see under your control rather than leaving it to whatever the surrounding expression happens to hand in.

Two per-SDK escape hatches, for a repo whose SDK build reads something outside its own directory:

```nix
sdks.nodejs = {
  lockFile = ./package-lock.json;
  npmDepsHash = "sha256-...";

  # Keep the whole tree for this SDK.
  narrowSrc = false;

  # ...or replace the default path list. Missing paths are skipped.
  srcPaths = [ "sdk/nodejs" "README.md" "LICENSE" "scripts/postinstall.js" ];
};
```

Both are also accepted by the builders directly as `nodejsArgs.narrowSrc`, `goArgs.srcPaths`, and so on.

### Consuming a nodejs SDK

A nodejs SDK - checked in or generated, npm or yarn - lands at `$out/lib/node_modules/<pkgName>`, holding the compiled output of `sdk/nodejs` plus its `package.json`, `README.md` and `LICENSE`, the shape Pulumi's own codegen publishes from.

`@pulumi/pulumi` is not shipped inside it.
It is a runtime `dependencies` entry of every generated SDK, but it has to be a *singleton* in the consuming process: Pulumi's Node runtime keeps the resource monitor address and the stack config at module scope, so a second copy is a second, unconfigured runtime.
Leaving it out also takes its transitive tree (`@grpc/grpc-js`, `typescript`, `ts-node`, `google-protobuf`) with it, which is most of the output - the `pulumi-command` example's nodejs SDK went from 165M to 200K.

Copy the package into your project rather than symlinking it:

```sh
mkdir -p node_modules/@unmango
cp -rL "$sdk/lib/node_modules/@unmango/pulumi-git" node_modules/@unmango/pulumi-git
```

Symlinking a store path does not work, and would not work with the copy bundled either: node and bun both resolve from the *realpath* of a symlink, so the SDK would look for `@pulumi/pulumi` under `/nix/store` and never see the one your program is using.
Copying puts the SDK inside your own `node_modules`, where it resolves the same `@pulumi/pulumi` your program does.

The output's `package.json` is upstream's, untouched: it still declares `@pulumi/pulumi` under `dependencies`, so a package manager pointed at the store path installs it for you.
Note that Pulumi's codegen emits no `main` or `types` field, so resolution falls back to `index.js`/`index.d.ts`.
That is fine under bun and `moduleResolution: "bundler"`, and worth knowing if anything stricter about `exports` ever enters the picture.

To change which dependencies are left out - to ship everything, or to treat another singleton the same way:

```nix
sdks.nodejs = {
  lockFile = ./package-lock.json;
  npmDepsHash = "sha256-...";

  # Default: [ "@pulumi/pulumi" ]. `[ ]` ships the whole pruned tree.
  omitDeps = [ "@pulumi/pulumi" "@pulumi/aws" ];
};
```

Also accepted directly as `nodejsArgs.omitDeps` / `yarnNodejsArgs.omitDeps`.

One difference between the two builders: npm drops the named packages before pruning, so anything reachable only through them goes too.
Yarn classic has no real `prune`, so `sdks.yarnNodejs` deletes them from the installed tree afterwards and their orphaned transitive dependencies stay behind.
Nothing resolves to those, but the output carries them.

### Overlay

As an alternative to threading `pkgs` through every builder call yourself, `pulumi2nix.overlays.default` applies every `lib` builder directly onto `pkgs`, pre-instantiated against it:

```nix
{
  inputs.pulumi2nix.url = "github:UnstoppableMango/pulumi2nix";

  outputs = { self, nixpkgs, pulumi2nix }: {
    packages.x86_64-linux =
      let
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          overlays = [ pulumi2nix.overlays.default ];
        };
      in
      {
        # pkgs.mkPulumiPackage, pkgs.mkComponentPackage, etc. are now
        # available directly.
        my-provider = pkgs.callPackage ./my-provider { };
      };
  };
}
```

### `mkPulumiSchema`

Produces just a native provider's `schema.json` by invoking its own `cmd/pulumi-gen-<name>` tool, without building the resource plugin binary.
See [`examples/pulumi-command-schema`](examples/pulumi-command-schema).

```nix
{ lib, mkPulumiSchema }:
mkPulumiSchema rec {
  owner = "pulumi";
  repo = "pulumi-command";
  version = "0.9.0";
  rev = "v${version}";
  hash = "sha256-...";
  vendorHash = "sha256-...";
  cmdGen = "pulumi-gen-command";
  extraLdflags = [ "-X github.com/pulumi/${repo}/provider/pkg/version.Version=v${version}" ];
  meta.license = lib.licenses.asl20;
}
```

### `mkPulumiPackage`

Builds the full `pulumi-resource-<name>` native provider plugin binary, and layers per-language SDKs (checked into the upstream repo's `sdk/<lang>`) on top via `<lang>Args` blocks.
See [`examples/pulumi-command`](examples/pulumi-command).

```nix
{ lib, mkPulumiPackage }:
mkPulumiPackage rec {
  owner = "pulumi";
  repo = "pulumi-command";
  version = "0.9.0";
  rev = "v${version}";
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

Derives `schema.json` from an upstream Terraform provider by driving `tfgen`'s `schema` language, without building the bridged plugin binary.
See [`examples/pulumi-random-schema`](examples/pulumi-random-schema).

```nix
{ lib, mkTerraformBridgeSchema }:
mkTerraformBridgeSchema rec {
  owner = "pulumi";
  repo = "pulumi-random";
  version = "4.14.0";
  rev = "v${version}";
  hash = "sha256-...";
  vendorHash = "sha256-...";
  cmdGen = "pulumi-tfgen-random";
  extraLdflags = [ "-X github.com/pulumi/${repo}/provider/v4/pkg/version.Version=v${version}" ];
  meta.license = lib.licenses.asl20;
}
```

### `mkTerraformBridgeProvider`

Builds the full `pulumi-tfgen-<name>` bridged provider plugin binary from an upstream Terraform provider, and layers per-language SDKs (checked into the upstream repo's `sdk/<lang>`) on top via `<lang>Args` blocks, same as `mkPulumiPackage`.
See [`examples/pulumi-random`](examples/pulumi-random).

```nix
{ lib, mkTerraformBridgeProvider }:
mkTerraformBridgeProvider rec {
  owner = "pulumi";
  repo = "pulumi-random";
  version = "4.14.0";
  rev = "v${version}";
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

Both this builder and `mkPulumiPackage` (which delegates to it) always build a python SDK, from the repo's checked-in `sdk/python` tree unless `pythonArgs.generate` swaps that for codegen.
Its distribution name defaults to `pulumi-` plus `cmdRes` with the `pulumi-resource-` prefix stripped, so `cmdRes = "pulumi-resource-random"` gives `pulumi-random`, matching the name tfgen writes into the generated SDK regardless of what the repo is called.
`pythonImportsCheck` is derived from that name by replacing `-` with `_`.
Pass `pythonArgs.pname` and `pythonArgs.pythonImportsCheck` (`sdks.python.*` in the flake module) for an SDK that does not follow the convention.

It also takes an optional `sdkDrift` block, which is what [SDK drift checks](#sdk-drift-checks) below are built from, and a per-language `generate` flag, which replaces the committed tree with codegen entirely - see [Generated SDKs for bridged providers](#generated-sdks-for-bridged-providers).

### SDK drift checks

`mkTerraformBridgeProvider` reads its per-language SDK source straight out of the source tree's `sdk/<lang>`, so a resource change that lands without a regenerated SDK still builds.
`checks.<name>-schema` rebuilds `schema.json` from source, but nothing compares the committed SDKs against it, and `nix flake check` stays green against a stale tree.

`sdkDrift.languages` closes that loop.
For each language listed it re-runs the provider's own `cmdGen` binary - the one the build already compiles - into a scratch directory and `diff -r`s the result against the committed `sdk/<lang>`, emitting `checks.<name>-sdk-<lang>-generated`.

```nix
pulumi.terraformBridgeProviders.pulumi-foo = {
  # ...
  sdkDrift.languages = [
    "nodejs"
    "python"
    "go"
    "dotnet"
  ];
};
```

The check is check-only: it never appears in `packages`, since its output is an empty marker file.

#### Bridges that delegate codegen

The plain list above assumes the gen tool emits every language itself, in-process and offline.
That was true of `pulumi-terraform-bridge` for a long time and is no longer.
On a current bridge, `pkg/tfgen`'s `emitSDK` routes Golang, NodeJS, Python and CSharp through `runPulumiPackageGenSDK`, which shells out to `pulumi package gen-sdk --language <lang>`.
A drift check on such a provider needs the `pulumi` CLI and that language's host on `PATH`, or the generator never runs at all and the check dies with `exec: "pulumi": executable file not found in $PATH`.

Say so by giving `languages` an attrset instead of a list, naming a `languagePlugin` per language:

```nix
pulumi.terraformBridgeProviders.pulumi-foo = {
  # ...
  sdkDrift.languages = {
    nodejs.languagePlugin = pkgs.pulumiPackages.pulumi-nodejs;
    python.languagePlugin = pkgs.pulumiPackages.pulumi-python;
    go.languagePlugin = pkgs.pulumiPackages.pulumi-go;
    dotnet = {
      languagePlugin = pulumi2nix.pulumiLanguageDotnet;
      extraExclude = [ "logo.png" ];
    };
  };
};
```

.NET has no `pulumi-language-dotnet` in nixpkgs, so it comes from this repo's `pulumiLanguageDotnet`, reachable as the `pulumi2nix` module argument.

Which of the two eras a provider is on is left to you, deliberately.
It follows from the `pulumi-terraform-bridge` version in the provider's own `provider/go.mod`, which nothing here can read at eval time, and guessing wrong in either direction is worse than asking: a missing plugin fails the check outright, and an unnecessary one drags the `pulumi` closure into a build that never invokes it.
Naming a plugin is the declaration.

Give `dotnet` `extraExclude = [ "logo.png" ]`.
`pulumiLanguageDotnet` carries an offline `pulumi_logo_64x64.png` so codegen works in the sandbox at all, which means the `logo.png` it emits is the generic Pulumi icon.
A committed SDK whose logo came from a real `logoUrl` fetch will therefore always read as drift.

Anything else set on a language (`exclude`, `extraExclude`, `sdkPath`) overrides the surrounding `sdkDrift` block for that language alone.

#### Excludes

`exclude` is the list of basenames `diff -r` skips.
It defaults to `package-lock.json`, `go.mod`, `go.sum` and `version.txt` - the files tfgen never emits, which are therefore committed by hand and would always read as drift.
Set `exclude` to replace that list outright, or `extraExclude` to add to it.
`logo.png` is deliberately not in the default: it is real drift for every language but .NET, so it is opted into per language rather than ignored for everyone.

It is off by default (`languages` starts empty), because it only makes sense where the committed SDK is reproducible from the pinned source:

- The repo must actually commit an `sdk/` tree. Not every declaration does, and a check with nothing to compare against would only ever fail.
- The repo's own generation step must be a plain `cmdGen <lang> --out sdk/<lang>`. Anything else the repo does on top (patching an `upstream/` submodule, running a Java generator, post-processing) is not replayed here.
- The gen tool must be able to find its documentation offline. Bridged providers that pull doc comments out of an upstream Terraform provider's `website/docs` cannot: nixpkgs vendors Go dependencies with `go mod vendor`, which keeps only `.go` files. [`examples/pulumi-random`](examples/pulumi-random) documents this case - the check there reports drift in every doc comment even though upstream's committed SDK is perfectly current.

Greenfield bridged providers, whose `make generate` is nothing but a tfgen invocation per language, are the case this is built for.

### Generated SDKs for bridged providers

A drift check is one of two answers to a stale `sdk/` tree.
The other is not to commit one: `sdks.<lang>.generate = true` codegens that language from the declaration's own `passthru.schema` instead of reading the repo's `sdk/<lang>`, so the tree and the `make generate` that maintains it can be deleted outright.

```nix
pulumi.terraformBridgeProviders.pulumi-foo = {
  # ...
  sdks.nodejs = {
    generate = true;
    languagePlugin = pkgs.pulumiPackages.pulumi-nodejs;
    lockFile = ./package-lock.json;
    npmDepsHash = "sha256-...";
  };

  sdks.python = {
    generate = true;
    languagePlugin = pkgs.pulumiPackages.pulumi-python;
  };
};
```

Pick one per language, not both: a generated SDK has no committed counterpart left for `sdkDrift` to diff against.
Languages left alone keep building from the repo, so a provider can generate some and commit others.

This runs the same `pulumi package gen-sdk` that [`mkGeneratedSdk`](#mkgeneratedsdk) uses for component providers, against the schema `checks.<name>-schema` already builds.
That is where a current tfgen ends up anyway - `pkg/tfgen`'s `emitSDK` shells out to exactly that command - so going straight to it needs no second generator, and each language needs its own `languagePlugin` for the same reason [the drift check does](#bridges-that-delegate-codegen).

#### Limitation: language overlays are not applied

`gen-sdk` is only the codegen step.
tfgen's per-language *overlays* - `info.JavaScript.Overlay`, `info.Golang.Overlay`, `info.Python.Overlay` and friends, the hand-written files a provider's `resources.go` splices into its SDKs around codegen - are not part of the schema, so nothing here can replay them.
A provider that ships overlays will get an SDK that silently lacks them.

That provider should keep its committed `sdk/` tree and guard it with [`sdkDrift`](#sdk-drift-checks) instead.
Generation is for providers whose SDKs are pure codegen output, which is most greenfield bridged providers.

#### What still comes from the caller

`gen-sdk` emits language sources and nothing else, so the caller-supplied module files stay required exactly as they are for a committed tree, and for the same reason they are required by [`mkComponentPackage`](#mkcomponentpackage):

- `nodejs` / `yarnNodejs`: `lockFile` + `npmDepsHash`, or `yarnLockFile` + `yarnDepsHash`.
- `go`: `vendorHash`, plus `importBasePath`, `goMod` and `goSum`. See [`mkGeneratedGoSdk`](#mkgeneratedgosdk) for what those are and how to produce them.
- `dotnet`: `nugetDeps`.

`narrowSrc` / `srcPaths` do not apply to a generated language: its source is codegen output, already scoped to the one language, with no shared repo tree left to cut down.

Python is generated in place by `mkTerraformBridgeProvider` rather than through `withGeneratedSdks`, which has no python builder ([Known Gaps](TODO.md)).
It needs no module files either way, so `generate` and `languagePlugin` are all `sdks.python` takes.

### `mkDynamicBridgeProvider`

Builds the generic `pulumi-resource-terraform-provider` binary, which dynamically bridges any Terraform provider at runtime rather than being generated ahead-of-time for one specific upstream provider like `mkTerraformBridgeProvider`.
`owner`/`repo` default to `pulumi`/`pulumi-terraform-bridge` (where the `dynamic` package actually lives; `pulumi/pulumi-terraform-provider` only hosts releases built from it), so most callers only need to pin `version`/`hash`/`vendorHash` (or `version`/`vendorHash` plus a [`src`](#overriding-the-source)).
See [`examples/pulumi-terraform-provider`](examples/pulumi-terraform-provider).

```nix
{ lib, mkDynamicBridgeProvider }:
mkDynamicBridgeProvider {
  version = "3.137.0";
  hash = "sha256-...";
  vendorHash = "sha256-...";
  meta.license = lib.licenses.asl20;
}
```

That shape builds a `pulumi-terraform-bridge` tag straight through.
Building what a `pulumi-terraform-provider` release actually shipped means pinning a commit instead, which is what the linked example does; see `versionString` below.

#### `versionString`

The binary reports a version of its own, compiled into `dynamic/version.version`, and `pulumi plugin ls` and the CLI's plugin-version resolution both read it.
`versionString` is what goes in there. It defaults to `rev`, which is right whenever the release tag and the source revision are the same string.

For this provider specifically they usually aren't.
`pulumi/pulumi-terraform-provider` hosts only docs and releases; the code is `pulumi/pulumi-terraform-bridge`'s `dynamic/` directory, and a `pulumi-terraform-provider` release names the bridge *commit* it was generated from rather than a bridge tag.
So a release-accurate build pins the SHA and names the tag separately:

```nix
{ lib, mkDynamicBridgeProvider }:
mkDynamicBridgeProvider {
  version = "1.1.3"; # names the derivation
  rev = "484f8987228cbec779e11f593bc48c79c49d4f08"; # the bridge commit the release was built from
  versionString = "v1.1.3"; # what the binary reports
  hash = "sha256-...";
  vendorHash = "sha256-...";
  meta.license = lib.licenses.asl20;
}
```

Without `versionString` that build still succeeds, and produces a binary reporting a 40-character SHA as its version.
`extraLdflags` can't fix it after the fact: it appends, so it cannot displace the `-X` already in the list, and `go build` taking the last `-X` for a symbol is an accident of ordering rather than a contract.

### `mkSchema`

The generic base builder underlying both `mkPulumiSchema` and `mkTerraformBridgeSchema` - takes an explicit `schemaCommand` invocation instead of assuming either wrapper's convention (tfgen's `schema` subcommand, or a native gen tool's `<out> --version <version>` flags). Use this directly when a provider's gen tool doesn't fit either convention.

```nix
{ lib, mkSchema }:
mkSchema rec {
  owner = "pulumi";
  repo = "pulumi-command";
  version = "0.9.0";
  rev = "v${version}";
  hash = "sha256-...";
  vendorHash = "sha256-...";
  cmdGen = "pulumi-gen-command";
  schemaCommand = "${cmdGen} schema.json --version ${version}"; # whatever this gen tool's own convention is
  meta.license = lib.licenses.asl20;
}
```

### `mkComponentSchema`

Extracts `schema.json` from a source-based, multi-language component provider (a directory carrying `PulumiPlugin.yaml`) by shelling out to `pulumi package get-schema`, which runs the component's own source directly.
See [`examples/test-component-schema`](examples/test-component-schema).

```nix
{ lib, mkComponentSchema, pulumiPackages }:
mkComponentSchema {
  pname = "test-component-schema";
  version = "0.0.1";
  src = ./.;
  languagePlugin = pulumiPackages.pulumi-nodejs;
  lockFile = ./package-lock.json;
  npmDepsHash = "sha256-...";
  # Optional: seed the plugin cache for components that import another
  # provider's SDK (e.g. @pulumi/github), since get-schema otherwise
  # tries to download that provider's resource plugin with no network
  # access in the sandbox.
  providerPlugins = [
    {
      name = "github";
      version = "6.15.0";
      plugin = pkgs.fetchurl { /* pulumi-resource-github tarball, extracted */ };
    }
  ];
  meta.license = lib.licenses.asl20;
}
```

**Component class shape.**
`pulumi package get-schema`'s analyzer only recognizes classes that extend `ComponentResource` directly - it walks one heritage-clause level and checks the resolved symbol against `resource.ts`/`resource.d.ts`.
A component extending an intermediate abstract base class (`Fork extends Repo extends ComponentResource`) is invisible to it, and fails with a generic "Failed to find the following components" error that gives no hint the cause is inheritance depth.
Keep component classes extending `ComponentResource` directly; push shared logic into a plain helper function instead of a shared base class.

The same analyzer also can't resolve utility or indexed-access types (`Omit<X, "y">`, `X["y"]`) in a component's args interface - it throws `Unsupported type for component ... property ...`.
Write args interfaces as plain, explicit fields instead.

**Untracked files.**
`src = ./.` in a flake only sees git-tracked files, so an untracked `PulumiPlugin.yaml` or lockfile needs `git add`ing before the build can see it - otherwise `mkComponentPackage`'s "expected PulumiPlugin.yaml" check fails misleadingly.

**Go module files.**
`pulumi package gen-sdk --language go` emits only `.go` sources: no `go.mod`, no `go.sum`.
A Go module path is external convention that upstream provider repos maintain by hand, and filling in a `require` block needs a real `go mod tidy` against the network, which a sandboxed derivation can't do.
So `goArgs` takes both files from the caller, the same way `nodejsArgs` takes a `package-lock.json`, plus an `importBasePath` - without it codegen falls back to an `example.com/...` path and writes self-imports that don't match the directories it just created, so the SDK cannot compile.

Regenerate them like this, then `git add` the results:

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
Keep the resulting `go` directive at or below the `go` version in your pinned nixpkgs, so the sandbox never tries to download a toolchain.
Then set `vendorHash = lib.fakeHash` and read the real hash out of the first build failure.

### `mkComponentPackage`

Packages a source-based component provider and layers generated SDKs on top of its extracted schema, since this provider shape has no compiled resource binary to build.
See [`examples/test-component`](examples/test-component).

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

### `mkGeneratedSdk`

The lower-level builder `<lang>Args` blocks resolve to under `mkComponentPackage`: runs `pulumi package gen-sdk` against a `schema.json` derivation, using the target language's `pulumi-language-<lang>` plugin.
Called directly, it is given a schema derivation (anything exposing `$out/schema.json`, e.g. the output of `mkPulumiSchema` or `mkComponentSchema`) rather than a whole package.
An optional `schemaOverrides` attrset is merged into the schema before codegen runs, which is how per-language settings get into a schema extracted from source (`mkComponentSchema` output carries none):

```nix
{ mkGeneratedSdk, pulumiPackages }:
mkGeneratedSdk {
  pname = "test-component";
  version = "0.0.1";
  schema = mkComponentSchema { /* ... */ };
  lang = "nodejs";
  languagePlugin = pulumiPackages.pulumi-nodejs;
  # schemaOverrides.language.go.importBasePath = "github.com/you/your-repo/sdk/go/yourcomponent";
  meta.license = lib.licenses.asl20;
}
```

### `mkGeneratedGoSdk`

Completes `mkGeneratedSdk`'s go output into a buildable module by copying a caller-supplied `go.mod`/`go.sum` into the module root, producing the `sdk/{go.mod,go.sum,go/...}` layout `lib/sdks/go.nix` expects.
`goArgs` under `mkComponentPackage` wires this up automatically; see **Go module files** above for how to produce the two files.

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

Not a package builder but a pinned build of the `pulumi-language-dotnet` host binary, filling the gap left by nixpkgs' `pulumiPackages` (which packages Go, Node.js, and Python language hosts, but not .NET).
It is patched so that its codegen reads a nix-fetched `pulumi_logo_64x64.png` instead of downloading one while writing each SDK's `logo.png`, which is what lets `pulumi package gen-sdk --language dotnet` run inside a build sandbox at all.
The tradeoff is that a schema's `logoUrl` no longer affects the generated `logo.png`: every .NET SDK gets the generic Pulumi icon, since an output that varied with network reachability would not be reproducible.

Feed its result as the `languagePlugin` for any `dotnetArgs` block above:

```nix
{ pkgs, flakeLib }:
let
  pulumiLanguageDotnet = flakeLib.pulumiLanguageDotnet;
in
# ... dotnetArgs.languagePlugin = pulumiLanguageDotnet;
```

## Development

Requires [Nix](https://nixos.org) with flakes enabled.

```sh
make build   # nix build .#
make check   # nix flake check
make fmt     # nix fmt
```

## License

[MIT](LICENSE)
