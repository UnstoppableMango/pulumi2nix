# pulumi2nix

[![CI](https://github.com/UnstoppableMango/pulumi2nix/actions/workflows/ci.yml/badge.svg)](https://github.com/UnstoppableMango/pulumi2nix/actions/workflows/ci.yml)
[![Built with Nix](https://img.shields.io/badge/built%20with-nix-5277C3?logo=nixos&logoColor=white)](https://builtwithnix.org)
[![License: MIT](https://img.shields.io/github/license/UnstoppableMango/pulumi2nix)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/UnstoppableMango/pulumi2nix)](https://github.com/UnstoppableMango/pulumi2nix/commits/main)

Composable Nix builders for Pulumi providers, packages, and language SDKs.

Every provider shape converges on one artifact, Pulumi's [package schema](https://www.pulumi.com/docs/iac/guides/building-extending/packages/schema/), and every builder here separates extracting it from packaging the plugin binary and SDKs downstream of it.
For what a provider *is* and how one is written, see Pulumi's [Build a Provider](https://www.pulumi.com/docs/iac/guides/building-extending/providers/build-a-provider/) guide; this repo only packages the result.

- [docs/usage.md](docs/usage.md) - every builder, its full argument shape, and the three entry points.
- [docs/sdks.md](docs/sdks.md) - `src` overrides, narrowed SDK sources, consuming a nodejs SDK, drift checks, generated SDKs.
- [docs/architecture.md](docs/architecture.md) - the artifact graph, the builder graph, and where the two disagree.
- [`examples/`](examples) - a buildable flake per builder.

One builder per artifact:

| Artifact builder | Builds |
| --- | --- |
| [`mkGenTool`](docs/usage.md#mkgentool) | the repo's `cmd/pulumi-{tf,}gen-<name>` binary |
| [`mkSchema`](docs/usage.md#mkschema) | `schema.json`, by running that gen tool |
| [`mkComponentSchema`](docs/usage.md#mkcomponentschema) | `schema.json` from component source via [`pulumi package get-schema`](https://www.pulumi.com/docs/iac/cli/commands/pulumi_package_get-schema/) |
| [`mkProviderPlugin`](docs/usage.md#mkproviderplugin) | the `pulumi-resource-<name>` binary, native or bridged |
| [`mkComponentPlugin`](docs/usage.md#mkcomponentplugin) | a component's source tree + `PulumiPlugin.yaml` |
| [`mkDynamicPlugin`](docs/usage.md#mkdynamicplugin) | the generic `pulumi-resource-terraform-provider` binary |
| [`mkSdkSource`](docs/usage.md#mksdksource) | one SDK source tree, committed or generated |
| [`mkSdk`](docs/usage.md#mksdk) | one packaged SDK |

And recipes that compose them:

| Recipe | Builds |
| --- | --- |
| [`mkPulumiPackage`](docs/usage.md#mkpulumipackage) | native provider: gen tool, schema, binary, SDKs |
| [`mkTerraformBridgeProvider`](docs/usage.md#mkterraformbridgeprovider) | the same, bridged from Terraform ahead of time |
| [`mkComponentPackage`](docs/usage.md#mkcomponentpackage) | component provider: schema, plugin tree, generated SDKs |
| [`mkDynamicBridgeProvider`](docs/usage.md#mkdynamicbridgeprovider) | the dynamic bridge, which has no schema and no SDKs |

Plus `mkPulumiSchema` / `mkTerraformBridgeSchema` (schema-command presets), [`withSdks`](docs/usage.md#withsdks), [`mkSdkDriftCheck`](docs/usage.md#mksdkdriftcheck), and [`pulumiLanguageDotnet`](docs/usage.md#pulumilanguagedotnet), a pinned [`pulumi-language-dotnet`](https://github.com/pulumi/pulumi-dotnet) host.

SDK codegen covers Node.js, Python, Go, and .NET. Java is not supported.

## Quick start

Declare a provider with the [flake-parts](https://flake.parts) module, which wires every build and its `passthru` outputs into `packages` and `checks`:

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
        };
      };
    };
}
```

That gives `packages.pulumi-random`, `.pulumi-random-schema`, `.pulumi-random-sdk-nodejs` and `.pulumi-random-sdk-python`, mirrored into `checks`.
One option tree per builder, and [the module's shape](docs/usage.md#flake-module) explains `sdks.<lang>`, freeform passthrough, and the naming rules.

Or take the builders directly, via `pulumi2nix.lib` or [the overlay](docs/usage.md#overlay):

```nix
flakeLib = pulumi2nix.lib { inherit pkgs; };
my-provider = pkgs.callPackage ./my-provider { inherit (flakeLib) mkPulumiPackage; };
```

## Samples

Minimal shapes only; [docs/usage.md](docs/usage.md) has the full argument list for each.

[`mkPulumiPackage`](docs/usage.md#mkpulumipackage), a native provider binary plus its committed SDKs ([example](examples/pulumi-command)):

```nix
{ mkPulumiPackage }:
mkPulumiPackage rec {
  owner = "pulumi";
  repo = "pulumi-command";
  version = "0.9.0";
  hash = "sha256-...";
  vendorHash = "sha256-...";
  cmdGen = "pulumi-gen-command";
  cmdRes = "pulumi-resource-command";
  nodejsArgs.lockFile = ./package-lock.json;
  nodejsArgs.npmDepsHash = "sha256-...";
}
```

[`mkTerraformBridgeProvider`](docs/usage.md#mkterraformbridgeprovider), the same for a provider bridged from Terraform ([example](examples/pulumi-random)):

```nix
{ mkTerraformBridgeProvider }:
mkTerraformBridgeProvider rec {
  owner = "pulumi";
  repo = "pulumi-random";
  version = "4.14.0";
  hash = "sha256-...";
  vendorHash = "sha256-...";
  cmdGen = "pulumi-tfgen-random";
  cmdRes = "pulumi-resource-random";
  nodejsArgs.lockFile = ./package-lock.json;
  nodejsArgs.npmDepsHash = "sha256-...";
}
```

[`mkDynamicBridgeProvider`](docs/usage.md#mkdynamicbridgeprovider), the generic binary behind Pulumi's [`terraform-provider`](https://www.pulumi.com/registry/packages/terraform-provider/) package ([example](examples/pulumi-terraform-provider)):

```nix
{ mkDynamicBridgeProvider }:
mkDynamicBridgeProvider {
  version = "1.1.3";                                 # names the derivation
  rev = "484f8987228cbec779e11f593bc48c79c49d4f08";  # bridge commit the release was built from
  versionString = "v1.1.3";                          # what the binary reports
  hash = "sha256-...";
  vendorHash = "sha256-...";
}
```

[`mkComponentSchema`](docs/usage.md#mkcomponentschema), a schema pulled out of a [component](https://www.pulumi.com/docs/iac/concepts/resources/components/) provider's own source ([example](examples/test-component-schema)):

```nix
{ mkComponentSchema, pulumiPackages }:
mkComponentSchema {
  pname = "test-component-schema";
  version = "0.0.1";
  src = ./.;
  languagePlugin = pulumiPackages.pulumi-nodejs;
  lockFile = ./package-lock.json;
  npmDepsHash = "sha256-...";
}
```

[`mkComponentPackage`](docs/usage.md#mkcomponentpackage), that component packaged with SDKs generated from its schema ([example](examples/test-component)):

```nix
{ mkComponentPackage, pulumiPackages }:
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
}
```

[`mkSdkSource`](docs/usage.md#mksdksource), one SDK's source tree from any schema derivation:

```nix
{ mkSdkSource, mkComponentSchema, pulumiPackages }:
mkSdkSource {
  pname = "test-component";
  version = "0.0.1";
  lang = "nodejs";
  schema = mkComponentSchema { /* ... */ };
  languagePlugin = pulumiPackages.pulumi-nodejs;
}
```

Pass `src` instead of `schema` for the repo's committed `sdk/<lang>`, or `genTool` to have the provider's own gen tool emit it.
[`mkSdk`](docs/usage.md#mksdk) turns any of those into a packaged SDK.

## Development

Requires [Nix](https://nixos.org) with flakes enabled.

```sh
make build   # nix build .#
make check   # nix flake check
make fmt     # nix fmt
```

## License

[MIT](LICENSE)
