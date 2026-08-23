# Known Gaps

## Java SDK generation

`lib/mk-generated-sdk.nix` can drive any language `pulumi package gen-sdk` supports, but nixpkgs' `pulumiPackages` has no `pulumi-language-java` to pass as `languagePlugin`, and there's no pinned build for it here the way `lib/pulumi-language-dotnet.nix` fills the .NET gap.
Closing this means packaging `pulumi/pulumi-java`'s language host, then registering a `java` entry in `lib/sdks/default.nix`.

## Python SDKs for component providers

`lib/with-generated-sdks.nix` throws on `pythonArgs`: only the languages registered in `lib/sdks` (nodejs, yarnNodejs, go, dotnet) are available for source-based component providers.
`mkPulumiPackage`/`mkTerraformBridgeProvider` don't have this gap - they delegate python to nixpkgs' upstream builder, which has no equivalent for a generated SDK tree.
The flake module mirrors this: `pulumi.componentPackages.<name>.sdks` has no `python` option, while `pulumi.nativeProviders`/`terraformBridgeProviders` do.

## SDK generation for bridged providers

`sdkDrift` (see the README) checks a bridged provider's committed `sdk/<lang>` against a fresh tfgen run, but the generation half still lives outside pulumi2nix.
`lib/with-generated-sdks.nix` exists for exactly this and is only wired to `mkComponentPackage`, because its generator is `pulumi package gen-sdk`, which needs a per-language `languagePlugin`.
A tfgen binary does not: it emits every language itself, offline, from the same `provider/` module the build already compiles.
An `sdks.<lang>.generate = true` that layers `with-generated-sdks.nix`-style behaviour onto the bridge builder with `cmdGen <lang>` as the generator would drop the committed `sdk/` tree entirely.
The caller-supplied-module-files caveat carries over: tfgen emits sources but no `package-lock.json`/`go.mod`/`go.sum`, so `lockFile`, `goMod` and `goSum` stay required.

## Drift checks against providers that vendor their docs

`sdkDrift` is exact only where the gen tool can reproduce the committed SDK offline.
Bridged providers that source doc comments from an upstream Terraform provider's `website/docs` cannot: nixpkgs vendors Go dependencies with `go mod vendor`, which keeps only `.go` files, so tfgen regenerates every resource with "could not find docs for resource ..." and the diff is all doc comments.
`examples/pulumi-random` documents the case and leaves the check off.
Closing it means getting the upstream module's non-Go files into the gen tool's environment, which nixpkgs' `buildGoModule` vendoring does not currently offer.
