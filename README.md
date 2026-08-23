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
`mkGeneratedSdk` runs `pulumi package gen-sdk` against a `schema.json` output using the target language's `pulumi-language-<lang>` plugin, covering Node.js, Python, and Go from nixpkgs' `pulumiPackages`, and .NET via this repo's own pinned `pulumi-language-dotnet` build (upstream `pulumi/pulumi-dotnet` has no packaged language host in nixpkgs). Java support is not yet implemented.
Go additionally goes through `mkGeneratedGoSdk`, which attaches the `go.mod`/`go.sum` pair that `gen-sdk` never emits.

## Usage

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
`repo` is still required either way, and `rev` still defaults to `v${version}`: both name the derivation, and `mkDynamicBridgeProvider` compiles `rev` into its version ldflag.

`sourceRoot` is resolved from the `src`'s name, so any fetcher output, a `lib.cleanSourceWith`, a plain path, and a store path all work.
Note the caveat below about `src = ./.` inside a flake only seeing git-tracked files.

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
  languagePlugin = pulumiPackages.pulumi-language-nodejs;
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
`src = ./.` in a flake only sees git-tracked files, so a newly added `PulumiPlugin.yaml` or lockfile needs `git add`ing before the build can see it - otherwise `mkComponentPackage`'s "expected PulumiPlugin.yaml" check fails misleadingly.

**Go module files.**
`pulumi package gen-sdk --language go` emits only `.go` sources: no `go.mod`, no `go.sum`.
A Go module path is external convention that upstream provider repos maintain by hand, and filling in a `require` block needs a real `go mod tidy` against the network, which a sandboxed derivation can't do.
So `goArgs` takes both files from the caller, the same way `nodejsArgs` takes a `package-lock.json`, plus an `importBasePath` - without it codegen falls back to an `example.com/...` path and writes self-imports that don't match the directories it just created, so the SDK cannot compile.

Regenerate them like this, then `git add` the results:

```sh
nix build .#your-package.schema --out-link /tmp/schema

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
    languagePlugin = pulumiPackages.pulumi-language-nodejs;
    lockFile = ./package-lock.json;
    npmDepsHash = "sha256-...";
  };
  nodejsArgs = {
    languagePlugin = pulumiPackages.pulumi-language-nodejs;
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
  languagePlugin = pulumiPackages.pulumi-language-nodejs;
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
