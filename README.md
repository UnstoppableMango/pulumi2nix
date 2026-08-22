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

- **Providers generated from non-Terraform schema sources.**
The same schema-then-package pattern extends to providers whose schema originates from OpenAPI or CloudFormation resource definitions, such as the `*-native` provider family, rather than from Terraform or a native Go generator.

- **Component provider packages.**
`mkComponentSchema` extracts a schema from a source-based, multi-language component provider (a directory carrying a `PulumiPlugin.yaml`) by shelling out to `pulumi package get-schema`, which launches the runtime's own `pulumi-language-<runtime>` host to serve the `GetSchema` RPC directly from source. `mkComponentPackage` packages that source tree and layers generated SDKs on top, since there is no compiled resource binary to build for this provider shape.

- **Schema generation, independent of the plugin binary.**
Every builder above separates schema extraction from binary packaging, so `schema.json` can be produced and consumed (for SDK generation, validation, or publishing) without paying for a full provider build.

- **Language SDK generation.**
`mkGeneratedSdk` runs `pulumi package gen-sdk` against a `schema.json` output using the target language's `pulumi-language-<lang>` plugin, covering Node.js, Python, and Go from nixpkgs' `pulumiPackages`, and .NET via this repo's own pinned `pulumi-language-dotnet` build (upstream `pulumi/pulumi-dotnet` has no packaged language host in nixpkgs). Java support is not yet implemented.

## Usage

Add this repo as a flake input, then obtain each builder via `callPackage` against `pulumi2nix.lib`.

```nix
{
  inputs.pulumi2nix.url = "github:UnstoppableMango/pulumi2nix";

  outputs = { self, nixpkgs, pulumi2nix }: {
    packages.x86_64-linux =
      let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        flakeLib = pulumi2nix.lib;
        mkPulumiPackage = flakeLib.mkPulumiPackage { inherit pkgs; };
      in
      {
        my-provider = pkgs.callPackage ./my-provider { inherit mkPulumiPackage; };
      };
  };
}
```

Each builder below is instantiated the same way: call the top-level function in `lib` with `pkgs` to get back a package-shaped function, then apply that to a provider's own arguments.
`mkPulumiPackage` and `mkTerraformBridgeProvider` also take an optional `nixpkgsPath`, used to locate nixpkgs' own Pulumi provider builder; it defaults to `pkgs.path`, so it only needs overriding when pinning a different nixpkgs revision than the one `pkgs` itself came from.
The full, buildable source for every example is under [`examples/`](examples); what follows is the trimmed shape of each one.

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
        # available directly, with nixpkgsPath already defaulted to
        # pkgs.path.
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

Builds the full `pulumi-tfgen-<name>` bridged provider plugin binary from an upstream Terraform provider.
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
  meta.license = lib.licenses.asl20;
}
```

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
  dotnetArgs = {
    languagePlugin = pulumiLanguageDotnet;
    nugetDeps = ./generated-sdk/dotnet/deps.json;
  };
  meta.license = lib.licenses.asl20;
}
```

### `mkGeneratedSdk`

The lower-level builder `<lang>Args` blocks resolve to under `mkComponentPackage`: runs `pulumi package gen-sdk` against a `schema.json` derivation, using the target language's `pulumi-language-<lang>` plugin.
Called directly, it is given a schema derivation (anything exposing `$out/schema.json`, e.g. the output of `mkPulumiSchema` or `mkComponentSchema`) rather than a whole package:

```nix
{ mkGeneratedSdk, pulumiPackages }:
mkGeneratedSdk {
  pname = "test-component";
  version = "0.0.1";
  schema = mkComponentSchema { /* ... */ };
  lang = "nodejs";
  languagePlugin = pulumiPackages.pulumi-language-nodejs;
  meta.license = lib.licenses.asl20;
}
```

### `pulumiLanguageDotnet`

Not a package builder but a pinned build of the `pulumi-language-dotnet` host binary, filling the gap left by nixpkgs' `pulumiPackages` (which packages Go, Node.js, and Python language hosts, but not .NET).
Feed its result as the `languagePlugin` for any `dotnetArgs` block above:

```nix
{ pkgs, flakeLib }:
let
  pulumiLanguageDotnet = flakeLib.pulumiLanguageDotnet { inherit pkgs; };
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
